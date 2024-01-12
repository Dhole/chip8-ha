use os;
use fmt;
use getopt;
use strconv;
use io;
use time;

use sdl2;
use sdl2::{ SDL_GameControllerAxis, SDL_EventType, SDL_RendererFlags,
	SDL_WindowFlags, SDLPixelFormatValues, SDL_TextureAccess, SDL_Texture,
	SDL_Keycode };
use chip8;

export fn main() void = {
	const res = run();
	defer run_deinit();
	match (res) {
	case let err: sdl2::error =>
		// Print the error before terminating because otherwise
		// SDL_Quit will free the error string.
		fmt::errorfln("SDL2 error: {}", sdl2::strerror(err))!;
		os::exit(-1);
	case void => void;
	};
};

fn run_deinit() void = {
	sdl2::SDL_Quit();
};

fn usage() never = {
	fmt::fatalf("usage: {} [-s --scale SCALE] ROM_PATH", os::args[0]);
};

fn keycode_to_mask(keycode: SDL_Keycode) u16 = {
	switch (keycode) {
	case SDL_Keycode::ONE => return 1 << 0x1;
	case SDL_Keycode::TWO => return 1 << 0x2;
	case SDL_Keycode::THREE => return 1 << 0x3;
	case SDL_Keycode::FOUR => return 1 << 0xc;
	case SDL_Keycode::q => return 1 << 0x4;
	case SDL_Keycode::w => return 1 << 0x5;
	case SDL_Keycode::e => return 1 << 0x6;
	case SDL_Keycode::r => return 1 << 0xd;
	case SDL_Keycode::a => return 1 << 0x7;
	case SDL_Keycode::s => return 1 << 0x8;
	case SDL_Keycode::d => return 1 << 0x9;
	case SDL_Keycode::f => return 1 << 0xe;
	case SDL_Keycode::z => return 1 << 0xa;
	case SDL_Keycode::x => return 1 << 0x0;
	case SDL_Keycode::c => return 1 << 0xb;
	case SDL_Keycode::v => return 1 << 0xf;
	case => return 0;
	};
};

fn run() (void | sdl2::error | io::EOF) = {
	const cmd = getopt::parse(os::args,
		"chip8-ha",
		('s', "scale", "Window scaling factor"),
		"files...",
	);
	defer getopt::finish(&cmd);

	let scale = 16;
	for (let i = 0z; i < len(cmd.opts); i += 1) {
		const opt = cmd.opts[i];
		switch (opt.0) {
		case 'e' =>
			scale = strconv::stoi(opt.1)!;
		case => abort(); // unreachable
		};
	};

	if (len(cmd.args) != 1) {
		fmt::printf("len(cmd.args) = {}", len(cmd.args))!;
		usage();
	};
	const path = cmd.args[0];

	const file = os::open(path)!;
	defer io::close(file)!;

	let rom = alloc([0u8...], chip8::MEM_SIZE);
	defer free(rom);
	let rom_size = 0z;
	for (true) {
		match (io::read(file, rom[rom_size..chip8::MEM_SIZE])!) {
		case io::EOF =>
			if (rom_size == 0) {
				return io::EOF;
			};
			break;
		case let n: size =>
			rom_size += n;
		};
	};

	let c8 = chip8::chip8(0);
	chip8::load_rom(&c8, rom[..rom_size])!;

	sdl2::SDL_Init(sdl2::SDL_INIT_VIDEO
		| sdl2::SDL_INIT_AUDIO)!;

	// TODO: Audio
	// const device = 

	const win = sdl2::SDL_CreateWindow("Chip8-ha by Dhole",
		sdl2::SDL_WINDOWPOS_CENTERED, sdl2::SDL_WINDOWPOS_CENTERED,
		chip8::SCREEN_WIDTH: int * scale, chip8::SCREEN_HEIGTH: int * scale,
		SDL_WindowFlags::OPENGL)?;
	defer sdl2::SDL_DestroyWindow(win);

	const render = sdl2::SDL_CreateRenderer(win, -1, SDL_RendererFlags::NONE)?;
	defer sdl2::SDL_DestroyRenderer(render);
	sdl2::SDL_SetRenderDrawColor(render, 0, 0, 0, 255)?;
	sdl2::SDL_RenderClear(render)?;
	sdl2::SDL_RenderPresent(render);

	const texture = sdl2::SDL_CreateTexture(render,
		SDLPixelFormatValues::SDL_PIXELFORMAT_RGB24,
		SDL_TextureAccess::SDL_TEXTUREACCESS_STREAMING,
		chip8::SCREEN_WIDTH: int, chip8::SCREEN_HEIGTH: int)?;
	defer sdl2::SDL_DestroyTexture(texture);

	const frame_duration = (1000000000i64 / 60): time::duration;
	// const frame_duration = (1000000000i64 / 1): time::duration;
	let keypad = 0u16;
	// Simulation of CRT non-instant pixel light up/down.
	let fb = alloc([0u16...], chip8::SCREEN_WIDTH * chip8::SCREEN_HEIGTH);
	defer free(fb);
	let timestamp = time::now(time::clock::MONOTONIC);
	for (true) {
		let ev = sdl2::event { ... };
		for (sdl2::SDL_PollEvent(&ev)? == 1) switch (ev.event_type) {
		case SDL_EventType::QUIT =>
			return;
		case SDL_EventType::KEYDOWN =>
			if (ev.key.keysym.sym == SDL_Keycode::ESCAPE) {
				return;
			};
			keypad |= keycode_to_mask(ev.key.keysym.sym);
		case SDL_EventType::KEYUP =>
			keypad &= ~keycode_to_mask(ev.key.keysym.sym);
		case => void;
		};
		chip8::frame(&c8, keypad)!;
		// TODO
		// if (c8.tone) {
		// 	device.resume();
		// } else {
		// 	device.pause();
		// };
		// fmt::printf("fb: {} {} {} {} {}\n", c8.fb[0], c8.fb[1], c8.fb[2], c8.fb[3], c8.fb[4])!;

		let pitch: int = 0;
		let pixels: nullable *u8 = null;
		sdl2::SDL_LockTexture(texture, null, &pixels: nullable * nullable *opaque, &pitch)?;
		let pixels = pixels: *u8;
		for (let y = 0u; y < chip8::SCREEN_HEIGTH; y += 1) {
			for (let x = 0u; x < chip8::SCREEN_WIDTH / 8; x += 1) {
				let byte = c8.fb[y * chip8::SCREEN_WIDTH / 8 + x];
				for (let i = 0u; i < 8; i += 1) {
					const offst = (y * pitch: uint + (x * 8 + i) * 3): uintptr;
					let fb_val = &fb[y * chip8::SCREEN_WIDTH + x * 8 + i];
					let on = (byte & 1 << (7 - i) != 0);
					// const FACTOR: u8 = 30;
					*fb_val = if (on)
						 511 - (511 - *fb_val) * 5 / 6
					else
						*fb_val * 5 / 6;
					// *fb_val = if (on) 255 else 0;
					let v = (if (255 < *fb_val) 255 else *fb_val): u8;
					*((pixels: uintptr + offst + 0): *u8) = v;
					*((pixels: uintptr + offst + 1): *u8) = v;
					*((pixels: uintptr + offst + 2): *u8) = v;
				};
			};
		};
		sdl2::SDL_UnlockTexture(texture);

		sdl2::SDL_RenderClear(render)?;
		sdl2::SDL_RenderCopy(render, texture, null, null)?;
		sdl2::SDL_RenderPresent(render);

		const now = time::now(time::clock::MONOTONIC);
		const sleep_dur = frame_duration - time::diff(timestamp, now);
		// fmt::printf("sleep_dur: {}\n", sleep_dur)!;
		sdl2::SDL_Delay((sleep_dur / 1000000): u32);
		// time::sleep(sleep_dur);
		timestamp = now;
	};
};
