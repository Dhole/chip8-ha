use os;
use fmt;
use getopt;
use strconv;
use io;
use time;

use sdl;
// use sdl2::{ SDL_GameControllerAxis, SDL_EventType, SDL_RendererFlags,
// 	SDL_WindowFlags, SDLPixelFormatValues, SDL_TextureAccess, SDL_Texture,
// 	SDL_Keycode };
use chip8;

export fn main() void = {
	const res = run();
	defer run_deinit();
	match (res) {
	case let err: sdl::error =>
		// Print the error before terminating because otherwise
		// SDL_Quit will free the error string.
		fmt::errorfln("SDL2 error: {}", sdl::strerror(err))!;
		os::exit(-1);
	case void => void;
	};
};

fn run_deinit() void = {
	sdl::quit();
};

fn usage() never = {
	fmt::fatalf("usage: {} [-s --scale SCALE] ROM_PATH", os::args[0]);
};

fn keycode_to_mask(keycode: sdl::key_code) u16 = {
	switch (keycode) {
	case sdl::key_code::_1 => return 1 << 0x1;
	case sdl::key_code::_2 => return 1 << 0x2;
	case sdl::key_code::_3 => return 1 << 0x3;
	case sdl::key_code::_4 => return 1 << 0xc;
	case sdl::key_code::q => return 1 << 0x4;
	case sdl::key_code::w => return 1 << 0x5;
	case sdl::key_code::e => return 1 << 0x6;
	case sdl::key_code::r => return 1 << 0xd;
	case sdl::key_code::a => return 1 << 0x7;
	case sdl::key_code::s => return 1 << 0x8;
	case sdl::key_code::d => return 1 << 0x9;
	case sdl::key_code::f => return 1 << 0xe;
	case sdl::key_code::z => return 1 << 0xa;
	case sdl::key_code::x => return 1 << 0x0;
	case sdl::key_code::c => return 1 << 0xb;
	case sdl::key_code::v => return 1 << 0xf;
	case => return 0;
	};
};

type square_wave = struct {
	phase_inc: f32,
	phase: f32,
	volume: f32,
};

fn square_wave_callback(userdata: nullable *opaque, stream: *u8, len_: int) void = {
	let state = userdata: *square_wave;
	for (let i = 0z; i < len_: size / size(f32); i += 1) {
		const v = if (state.phase <= 0.5)
			state.volume
		else
			-state.volume;
		*((stream: uintptr + i: uintptr * size(f32)): *f32) = v;
		state.phase = (state.phase + state.phase_inc);
		if (state.phase > 1.0) {
			state.phase -= 1.0;
		};
	};
};

fn run() (void | sdl::error | io::EOF) = {
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

	sdl::init(sdl::init_flags::VIDEO | sdl::init_flags::AUDIO)!;

	const freq: int = 44100;
	const square_wave_state = square_wave {
		phase_inc = 440.0 / freq: f32,
		phase = 0.0,
		volume = 0.25,
	};
	const spec = sdl::audio_spec {
		freq = freq,
		format = sdl::audio_format::F32,
		channels = 1,
		silence = 0,
		samples = 0,
		padding = 0,
		size_ = 0,
		callback = &square_wave_callback,
		userdata = &square_wave_state,
	};
	const _obtained = spec; // copy to be overwritten
	const audio_dev = sdl::open_audio_device(void, 0, &spec, &_obtained, 0)!;
	defer sdl::close_audio_device(audio_dev);

	const win = sdl::create_window("Chip8-ha by Dhole",
		sdl::WINDOWPOS_CENTERED, sdl::WINDOWPOS_CENTERED,
		chip8::SCREEN_WIDTH: int * scale, chip8::SCREEN_HEIGTH: int * scale,
		sdl::window_flags::OPENGL)?;
	defer sdl::destroy_window(win);

	const render = sdl::create_renderer(win, -1, sdl::renderer_flags::NONE)?;
	defer sdl::destroy_renderer(render);
	sdl::set_render_draw_color(render, 0, 0, 0, 255)?;
	sdl::render_clear(render)?;
	sdl::render_present(render);

	const texture = sdl::create_texture(render,
		sdl::pixel_format_value::RGB24,
		sdl::texture_access::STREAMING: int,
		chip8::SCREEN_WIDTH: int, chip8::SCREEN_HEIGTH: int)?;
	defer sdl::destroy_texture(texture);

	const frame_duration = (1000000000i64 / 60): time::duration;
	// const frame_duration = (1000000000i64 / 1): time::duration;
	let keypad = 0u16;
	// Simulation of CRT non-instant pixel light up/down.
	let fb = alloc([0u16...], chip8::SCREEN_WIDTH * chip8::SCREEN_HEIGTH);
	defer free(fb);
	let timestamp = time::now(time::clock::MONOTONIC);
	for (true) {
		for (true) match (sdl::poll_event()) {
		case void => break;
		case sdl::quit_requested =>
			return;
		case let key: sdl::key_pressed =>
			if (key.keysym.sym: sdl::key_code == sdl::key_code::ESCAPE) {
				return;
			};
			keypad |= keycode_to_mask(key.keysym.sym: sdl::key_code);
		case let key: sdl::key_released =>
			keypad &= ~keycode_to_mask(key.keysym.sym: sdl::key_code);
		case => break;
		};
		chip8::frame(&c8, keypad)!;
		if (c8.tone) {
			sdl::pause_audio_device(audio_dev, false);
		} else {
			sdl::pause_audio_device(audio_dev, true);
		};
		// fmt::printf("fb: {} {} {} {} {}\n", c8.fb[0], c8.fb[1], c8.fb[2], c8.fb[3], c8.fb[4])!;

		let pitch: int = 0;
		let pixels: nullable *u8 = null;
		sdl::lock_texture(texture, null, &pixels: **opaque, &pitch)?;
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
		sdl::unlock_texture(texture);

		sdl::render_clear(render)?;
		sdl::render_copy(render, texture, null, null)?;
		sdl::render_present(render);

		const now = time::now(time::clock::MONOTONIC);
		const sleep_dur = frame_duration - time::diff(timestamp, now);
		// fmt::printf("sleep_dur: {}\n", sleep_dur)!;
		sdl::delay((sleep_dur / 1000000): u32);
		// time::sleep(sleep_dur);
		timestamp = now;
	};
};
