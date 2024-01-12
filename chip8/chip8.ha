use fmt;
use math::random;

// Op descriptions are taken from Cowgod's Chip-8 Technical Reference v1.0  compiled by Thomas P.
// Greene: http://devernay.free.fr/hacks/chip8/C8TECH10.HTM

export const SCREEN_WIDTH: uint = 64;
export const SCREEN_HEIGTH: uint = 32;

const SPRITE_CHARS: [0x10][5]u8 = [
    [0xF0, 0x90, 0x90, 0x90, 0xF0], // 0
    [0x20, 0x60, 0x20, 0x20, 0x70], // 1
    [0xF0, 0x10, 0xF0, 0x80, 0xF0], // 2
    [0xF0, 0x10, 0xF0, 0x10, 0xF0], // 3
    [0x90, 0x90, 0xF0, 0x10, 0x10], // 4
    [0xF0, 0x80, 0xF0, 0x10, 0xF0], // 5
    [0xF0, 0x80, 0xF0, 0x90, 0xF0], // 6
    [0xF0, 0x10, 0x20, 0x40, 0x40], // 7
    [0xF0, 0x90, 0xF0, 0x90, 0xF0], // 8
    [0xF0, 0x90, 0xF0, 0x10, 0xF0], // 9
    [0xF0, 0x90, 0xF0, 0x90, 0x90], // A
    [0xE0, 0x90, 0xE0, 0x90, 0xE0], // B
    [0xF0, 0x80, 0x80, 0x80, 0xF0], // C
    [0xE0, 0x90, 0x90, 0x90, 0xE0], // D
    [0xF0, 0x80, 0xF0, 0x80, 0xF0], // E
    [0xF0, 0x80, 0xF0, 0x80, 0x80], // F
];

const SPRITE_CHARS_ADDR: u16 = 0x0000;
export const MEM_SIZE: uint = 0x1000;
const ROM_ADDR: uint = 0x200;

export type ErrInvalidOp = struct {
	words: [2]u8,
};
export type ErrRomTooBig = struct {
	rom_size: uint,
};
export type ErrPcOutOfBounds = struct {
	pc: u16,
};
export type ErrDebug = void;
export type Error = !(ErrInvalidOp | ErrRomTooBig | ErrPcOutOfBounds | ErrDebug);

// Returns low nibble from byte
fn lo_nib(b: u8) u8 = {
    return b & 0x0f;
};

// Returns high nibble from byte
fn hi_nib(b: u8) u8 = {
    return (b & 0xf0) >> 4;
};

// Build a 3 nibble double word from two words
fn nnn(w0: u8, w1: u8) u16 = {
	return (w0 & 0x0f): u16 << 8 | w1: u16;
};

export type Chip8 = struct {
	mem: []u8,
	v: [0x10]u8, // Register Set
	i: u16,  // Index Register
	pc: u16, // Program Counter
	stack: [0x10]u16,
	sp: u8,                                   // Stack Pointer
	dt: u8,                                   // Delay Timer
	st: u8,                                   // Sound Timer
	keypad: u16,                              // Keypad
	fb: []u8, // Framebuffer
	tone: bool,                               // Tone output enable
	time: int,                                // Overtime in microseconds
	random: random::random,                   // State of the random number generator
};

// Creates a new chip8 emulator with a seed for its randomness.  Must be freed
// with [[chip8_free]].
export fn chip8(seed: u64) Chip8 = {
	let mem = alloc([0u8...], MEM_SIZE);
	for (let i = 0u; i < len(SPRITE_CHARS); i += 1) {
		const sprite = SPRITE_CHARS[i];
		const p = SPRITE_CHARS_ADDR: uint + i * len(sprite);
		mem[p..p + len(sprite)] = sprite[..];
	};
	return Chip8 {
		mem = mem,
		v = [0...],
		i = 0,
		pc = ROM_ADDR: u16,
		stack = [0...],
		sp = 0,
		dt = 0,
		st = 0,
		keypad = 0,
		fb = alloc([0...], SCREEN_WIDTH * SCREEN_HEIGTH / 8),
		tone = false,
		time = 0,
		random = random::init(seed),
	};
};

export fn chip8_free(c8: *Chip8) void = {
	free(c8.mem);
	free(c8.fb);
};

// Load a rom into Chip8 memory
export fn load_rom(c8: *Chip8, rom: []u8) (void | Error) = {
	const len_rom = len(rom): uint;
	if (len_rom > MEM_SIZE - ROM_ADDR) {
            return ErrRomTooBig { rom_size = len_rom };
        };
        c8.mem[ROM_ADDR..ROM_ADDR + len_rom] = rom;
	return void;
};

const FRAME_TIME: int = 16666; // In microseconds

// Emulates the execution of instructions continuously until the emulated instructions total
// elapsed time reaches the equivalent of a frame.
export fn frame(c8: *Chip8, keypad: u16) (void | Error) = {
	c8.keypad = keypad;
	if (c8.dt != 0) {
		c8.dt -= 1;
	};
	c8.tone = if (c8.st != 0) {
		c8.st -= 1;
		yield true;
	} else false;
	c8.time += FRAME_TIME;

	for (c8.time > 0) {
		if (c8.pc: uint > MEM_SIZE - 1) {
			return ErrPcOutOfBounds{pc = c8.pc};
		};
		let w0 = c8.mem[c8.pc: uint];
		let w1 = c8.mem[c8.pc: uint + 1];
		// fmt::printf("pc: {}\n", c8.pc)!;
		let adv = exec(c8, w0, w1)?;
		c8.time -= adv: int;
	};
	return;
};

// Op: Clear the display.
fn op_cls(c8: *Chip8) uint = {
	c8.fb[..] = [0...];
	c8.pc += 2;
	return 109;
};

fn op_call_rca_1802(c8: *Chip8, _addr: u16) uint = {
	return 100;
};

// Op: Return from a subroutine.
fn op_ret(c8: *Chip8) uint = {
	c8.sp -= 1;
	c8.pc = c8.stack[c8.sp: uint];
	return 105;
};

// Op: Jump to addr.
fn op_jp(c8: *Chip8, addr: u16) uint = {
	c8.pc = addr;
	return 105;
};

// Op: Call subroutine at addr.
fn op_call(c8: *Chip8, addr: u16) uint = {
	c8.stack[c8.sp: uint] = c8.pc + 2;
	c8.sp += 1;
	c8.pc = addr;
	return 105;
};

// Op: Skip next instruction if a == b.
fn op_se(c8: *Chip8, a: u8, b: u8) uint = {
	if (a == b) {
		c8.pc += 4;
	} else {
		c8.pc += 2;
	};
	return 61;
};

// Op: Skip next instruction if a != b.
fn op_sne(c8: *Chip8, a: u8, b: u8) uint = {
	if (a != b) {
		c8.pc += 4;
	} else {
		c8.pc += 2;
	};
	return 61;
};

// Op: Set Vx = v.
fn op_ld(c8: *Chip8, x: uint, v: u8) uint = {
	c8.v[x] = v;
	c8.pc += 2;
	return 27;
};

// Op: Wait for a key press, store the value of the key in Vx.
fn op_ld_vx_k(c8: *Chip8, x: uint) uint = {
	for (let i = 0u16; i < 0x10; i += 1) {
		if (1 << i & c8.keypad != 0) {
			c8.v[x] = i: u8;
			c8.pc += 2;
			break;
		};
	};
	return 200;
};

// Op: Set delay timer = Vx.
fn op_ld_dt(c8: *Chip8, v: u8) uint = {
	c8.dt = v;
	c8.pc += 2;
	return 45;
};

// Op: Set sound timer = Vx.
fn op_ld_st(c8: *Chip8, v: u8) uint = {
	c8.st = v;
	c8.pc += 2;
	return 45;
};

// Op: Set I = location of sprite for digit v.
fn op_ld_f(c8: *Chip8, v: u8) uint = {
	c8.i = SPRITE_CHARS_ADDR + v: u16 * 5;
	c8.pc += 2;
	return 91;
};

// Op: Store BCD representation of v in memory locations I, I+1, and I+2.
fn op_ld_b(c8: *Chip8, v: u8) uint = {
	const d2 = v / 100;
	let v = v - d2 * 100;
	const d1 = v / 10;
	let v = v - d1 * 10;
	const d0 = v / 1;
	c8.mem[c8.i: uint + 0] = d2;
	c8.mem[c8.i: uint + 1] = d1;
	c8.mem[c8.i: uint + 2] = d0;
	c8.pc += 2;
	return 927;
};

// Op: Store registers V0 through Vx in memory starting at location I.
fn op_ld_i_vx(c8: *Chip8, x: u8) uint = {
	for (let i = 0u8; i < x+1; i += 1) {
		c8.mem[c8.i: uint + i: uint] = c8.v[i];
	};
	c8.pc += 2;
	return 605;
};

// Op: Read registers V0 through Vx from memory starting at location I.
fn op_ld_vx_i(c8: *Chip8, x: u8) uint = {
	for (let i = 0u8; i < x+1; i += 1) {
		c8.v[i] = c8.mem[c8.i: uint + i: uint];
	};
	c8.pc += 2;
	return 605;
};

// Op: Set Vx = Vx + b.
fn op_add(c8: *Chip8, x: uint, b: u8, set_overflow: bool) uint = {
	const overflow = c8.v[x]: uint + b: uint > 0xff;
	const res = c8.v[x] + b;
	c8.v[x] = res;
	if (set_overflow) {
		c8.v[0xf] = if (overflow) 1 else 0;
	};
	c8.pc += 2;
	return 45;
};

// Op: Set I = I + b.
fn op_add16(c8: *Chip8, b: u8) uint = {
	c8.i += b: u16;
	c8.pc += 2;
	return 86;
};

// Op: Set Vx = Vx OR b.
fn op_or(c8: *Chip8, x: uint, b: u8) uint = {
	c8.v[x] |= b;
	c8.pc += 2;
	return 200;
};

// Op: Set Vx = Vx AND b.
fn op_and(c8: *Chip8, x: uint, b: u8) uint = {
	c8.v[x] &= b;
	c8.pc += 2;
	return 200;
};

// Op: Set Vx = Vx XOR b.
fn op_xor(c8: *Chip8, x: uint, b: u8) uint = {
	c8.v[x] ^= b;
	c8.pc += 2;
	return 200;
};

// Op: Set Vx = Vx - b.
fn op_sub(c8: *Chip8, x: uint, b: u8) uint = {
	const overflow = c8.v[x] - b > c8.v[x];
	const res = c8.v[x] - b;
	c8.v[x] = res;
	c8.v[0xf] = if (overflow) 0 else 1;
	c8.pc += 2;
	return 200;
};

// Op: Set Vx = b - Vx, set Vf = NOT borrow.
fn op_subn(c8: *Chip8, x: uint, b: u8) uint = {
	const overflow = b - c8.v[x] > b;
	const res = b - c8.v[x];
	c8.v[x] = res;
	c8.v[0xf] = if (overflow) 0 else 1;
	c8.pc += 2;
	return 200;
};

// Op: Set Vx = Vx >> 1.
fn op_shr(c8: *Chip8, x: uint) uint = {
	c8.v[0xf] = c8.v[x] & 0b00000001;
	const res = c8.v[x] >> 1;
	c8.v[x] = res;
	c8.pc += 2;
	return 200;
};

// Op: Set Vx = Vx << 1.
fn op_shl(c8: *Chip8, x: uint) uint = {
	c8.v[0xf] = (c8.v[x] & 0b10000000) >> 7;
	const res = c8.v[x] << 1;
	c8.v[x] = res;
	c8.pc += 2;
	return 200;
};

// Op: Set I = addr
fn op_ld_i(c8: *Chip8, addr: u16) uint = {
	c8.i = addr;
	c8.pc += 2;
	return 55;
};

// Op: Set Vx = random byte AND v
fn op_rnd(c8: *Chip8, x: uint, v: u8) uint = {
	c8.v[x] = (random::next(&c8.random): u8) & v;
	c8.pc += 2;
	return 164;
};

// Op: Display n-byte sprite starting at memory location I at (Vx, Vy), set VF = collision.
fn op_drw(c8: *Chip8, pos_x: u8, pos_y: u8, n: u8) uint = {
	const pos_x = pos_x % 64;
	const pos_y = pos_y % 32;
	const fb = c8.fb;
	const shift = pos_x % 8;
	const col_a = pos_x: uint / 8;
	const col_b = (col_a + 1) % (SCREEN_WIDTH / 8);
	let collision = 0u8;
	for (let i = 0u8; i < n; i += 1) {
	    const byte = c8.mem[c8.i: uint + i];
	    const y = (pos_y: uint + i) % SCREEN_HEIGTH;
	    const a = byte >> shift;
	    const fb_a = &fb[y * SCREEN_WIDTH / 8 + col_a];
	    collision |= *fb_a & a;
	    *fb_a ^= a;
	    if (shift != 0) {
		const b = byte << (8 - shift);
		const fb_b = &fb[y * SCREEN_WIDTH / 8 + col_b];
		collision |= *fb_b & b;
		*fb_b ^= b;
	    };
	};
	c8.v[0xf] = if (collision != 0) 1 else 0;
	c8.pc += 2;
	return 22734;
};

// Op: Skip next instruction if key with the value of v is pressed.
fn op_skp(c8: *Chip8, v: u8) uint = {
	if (1 << v & c8.keypad != 0) {
		c8.pc += 4;
	} else {
		c8.pc += 2;
	};
	return 73;
};

// Op: Skip next instruction if key with the value of v is not pressed.
fn op_sknp(c8: *Chip8, v: u8) uint = {
	if (1 << v & c8.keypad == 0) {
		c8.pc += 4;
	} else {
		c8.pc += 2;
	};
	return 73;
};

// Execute the instruction defined by (w0, w1).  Returns the number of microseconds elapsed.
fn exec(c8: *Chip8, w0: u8, w1: u8) (uint | Error) = {
	switch (w0 & 0xf0) {
	case 0x00 => switch(w1) {
		case 0xe0 => return op_cls(c8);
		case 0xee => return op_ret(c8);
		case => return op_call_rca_1802(c8, nnn(w0, w1));
	};
	case 0x10 => return op_jp(c8, nnn(w0, w1));
	case 0x20 => return op_call(c8, nnn(w0, w1));
	case 0x30 => return op_se(c8, c8.v[lo_nib(w0)], w1);
	case 0x40 => return op_sne(c8, c8.v[lo_nib(w0)], w1);
	case 0x50 => return op_se(c8, c8.v[lo_nib(w0)], c8.v[hi_nib(w1)]);
	case 0x60 => return op_ld(c8, w0 & 0x0f, w1);
	case 0x70 => return op_add(c8, w0 & 0x0f, w1, false);
	case 0x80 => {
		const a = lo_nib(w0);
		const b = c8.v[hi_nib(w1)];
		switch (w1 & 0x0f) {
		case 0x00 => return op_ld(c8, a, b);
		case 0x01 => return op_or(c8, a, b);
		case 0x02 => return op_and(c8, a, b);
		case 0x03 => return op_xor(c8, a, b);
		case 0x04 => return op_add(c8, a, b, true);
		case 0x05 => return op_sub(c8, a, b);
		case 0x06 => return op_shr(c8, a);
		case 0x07 => return op_subn(c8, a, b);
		case 0x0E => return op_shl(c8, a);
		case => return ErrInvalidOp{words=[w0, w1]};
		};
	};
	case 0x90 => switch (w1 & 0x0f) {
		case 0x00 => return op_sne(c8, c8.v[lo_nib(w0)], c8.v[hi_nib(w1)]);
		case => return ErrInvalidOp{words=[w0, w1]};
	};
	case 0xA0 => return op_ld_i(c8, nnn(w0, w1));
	case 0xB0 => return op_jp(c8, c8.v[0]: u16 + nnn(w0, w1));
	case 0xC0 => return op_rnd(c8, lo_nib(w0), w1);
	case 0xD0 => return op_drw(c8, c8.v[lo_nib(w0)], c8.v[hi_nib(w1)], lo_nib(w1));
	case 0xE0 => switch (w1) {
		case 0x9E => return op_skp(c8, c8.v[lo_nib(w0)]);
		case 0xA1 => return op_sknp(c8, c8.v[lo_nib(w0)]);
		case => return ErrInvalidOp{words=[w0, w1]};
	};
	case 0xF0 => switch (w1) {
		case 0x07 => return op_ld(c8, lo_nib(w0), c8.dt);
		case 0x0A => return op_ld_vx_k(c8, lo_nib(w0));
		case 0x15 => return op_ld_dt(c8, c8.v[lo_nib(w0)]);
		case 0x18 => return op_ld_st(c8, c8.v[lo_nib(w0)]);
		case 0x1E => return op_add16(c8, c8.v[lo_nib(w0)]);
		case 0x29 => return op_ld_f(c8, c8.v[lo_nib(w0)]);
		case 0x33 => return op_ld_b(c8, c8.v[lo_nib(w0)]);
		case 0x55 => return op_ld_i_vx(c8, lo_nib(w0));
		case 0x65 => return op_ld_vx_i(c8, lo_nib(w0));
		case => return ErrInvalidOp{words=[w0, w1]};
	};
	case => return ErrInvalidOp{words=[w0, w1]};
	};
};
