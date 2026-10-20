//! Headless runner for `columns.asm` built on Saturn's own backend.
//!
//! It assembles the program with Saturn's assembler, executes it on Saturn's MIPS
//! CPU with Saturn's syscall + keyboard-MMIO implementations, and swaps the real
//! clock for a virtual one so every `sleep` syscall is one deterministic "tick".
//! On each tick a small bot reads the game state, presses keys, and the bitmap
//! display (0x10008000, 32x32 units) is dumped so it can be turned into PNG/GIFs.
//!
//! Usage: saturn-capture <columns.asm> <out-dir> [difficulty=2] [play-pieces=30]

use async_trait::async_trait;
use futures::executor::block_on;
use saturn_backend::build::{assemble_text, AssemblerResult};
use saturn_backend::keyboard::{configure_keyboard, KeyboardState};
use saturn_backend::mips::device::{setup_state, state_from_binary};
use saturn_backend::platforms::Platform;
use saturn_backend::syscall::{
    ConsoleHandler, MidiHandler, MidiRequest, SyscallDelegate, SyscallState, TimeHandler,
};
use std::collections::{HashMap, VecDeque};
use std::fs::File;
use std::future::Future;
use std::io::Write;
use std::path::Path;
use std::pin::Pin;
use std::sync::atomic::{AtomicU64, AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;
use titan::cpu::memory::section::SectionMemory;
use titan::cpu::Memory;
use titan::execution::trackers::empty::EmptyTracker;
use titan::execution::{Executor, ExecutorMode};
use titan::mips::cpu::registers::registers::RawRegisters;
use titan::mips::cpu::Registers;

const DISPLAY: u32 = 0x10008000;
const W: u32 = 32;
const H: u32 = 32;
const ROW: u32 = 128; // bytes per display row

// Playfield interior (see columns.asm: walls at x=1, x=8, y=1, y=15)
const X0: i32 = 2;
const X1: i32 = 7;
const Y0: i32 = 2;
const Y1: i32 = 14;

// ---------------------------------------------------------------- handlers

struct VirtualClock(AtomicU64);

#[async_trait]
impl TimeHandler for VirtualClock {
    fn time(&self) -> Option<Duration> {
        Some(Duration::from_millis(self.0.load(Ordering::SeqCst)))
    }

    async fn sleep(&self, duration: Duration) {
        self.0.fetch_add(duration.as_millis() as u64, Ordering::SeqCst);
    }
}

struct Console(Arc<Mutex<String>>);

impl ConsoleHandler for Console {
    fn print(&mut self, text: &str, _error: bool) {
        eprint!("{text}");
        self.0.lock().unwrap().push_str(text);
    }
}

// No synthesiser headless: count requested notes, report "not installed" so
// syscall 31/33 return immediately instead of waiting on audio playback.
struct Midi(Arc<AtomicUsize>);

impl MidiHandler for Midi {
    fn play(&mut self, _request: &MidiRequest, _sync: bool) {}

    fn install(&mut self, _instrument: u32) -> Pin<Box<dyn Future<Output = bool> + Send>> {
        Box::pin(async { false })
    }

    fn installed(&mut self, _instrument: u32) -> bool {
        self.0.fetch_add(1, Ordering::SeqCst);
        false
    }
}

// ---------------------------------------------------------------- board sim

type Board = [[u32; 13]; 6]; // [x - X0][y - Y0], 0 = empty

fn cell(b: &Board, x: i32, y: i32) -> Option<u32> {
    if (X0..=X1).contains(&x) && (Y0..=Y1).contains(&y) {
        Some(b[(x - X0) as usize][(y - Y0) as usize])
    } else {
        None // wall
    }
}

fn set(b: &mut Board, x: i32, y: i32, c: u32) {
    b[(x - X0) as usize][(y - Y0) as usize] = c;
}

fn column_top(b: &Board, x: i32) -> i32 {
    (Y0..=Y1).find(|&y| cell(b, x, y) != Some(0)).unwrap_or(Y1 + 1)
}

/// Clears every 3-in-a-row (any direction), collapses, repeats. Returns (cells cleared, chains).
fn resolve(b: &mut Board) -> (u32, u32) {
    let (mut cleared, mut chains) = (0, 0);
    loop {
        let mut mark = [[false; 13]; 6];
        let mut any = false;
        for x in X0..=X1 {
            for y in Y0..=Y1 {
                let c = cell(b, x, y).unwrap();
                if c == 0 {
                    continue;
                }
                for (dx, dy) in [(1, 0), (0, 1), (1, 1), (-1, 1)] {
                    if cell(b, x + dx, y + dy) == Some(c) && cell(b, x + 2 * dx, y + 2 * dy) == Some(c) {
                        for k in 0..3 {
                            mark[(x + k * dx - X0) as usize][(y + k * dy - Y0) as usize] = true;
                        }
                        any = true;
                    }
                }
            }
        }
        if !any {
            return (cleared, chains);
        }
        chains += 1;
        for x in 0..6 {
            let kept: Vec<u32> = (0..13).filter(|&y| !mark[x][y] && b[x][y] != 0).map(|y| b[x][y]).collect();
            cleared += (0..13).filter(|&y| mark[x][y]).count() as u32;
            let mut col = [0u32; 13];
            for (i, c) in kept.iter().rev().enumerate() {
                col[12 - i] = *c;
            }
            b[x] = col;
        }
    }
}

fn rotate(c: [u32; 3], times: usize) -> [u32; 3] {
    // `w` in columns.asm: (c1, c2, c3) <- (c2, c3, c1)
    let mut c = c;
    for _ in 0..times {
        c = [c[1], c[2], c[0]];
    }
    c
}

/// Drops a piece into column x. Returns None if it would end the game.
fn place(b: &Board, x: i32, colours: [u32; 3]) -> Option<(Board, u32, u32)> {
    let land = column_top(b, x) - 3;
    if land < 3 {
        return None; // landing at the spawn row is game over
    }
    let mut nb = *b;
    for k in 0..3 {
        set(&mut nb, x, land + k, colours[k as usize]);
    }
    let (cleared, chains) = resolve(&mut nb);
    Some((nb, cleared, chains))
}

fn heuristic(b: &Board) -> f64 {
    let mut score = 0.0;
    for x in X0..=X1 {
        let height = (Y1 + 1 - column_top(b, x)) as f64;
        score -= height * 4.0 + if height > 8.0 { 60.0 } else { 0.0 };
        for y in Y0..=Y1 {
            let c = cell(b, x, y).unwrap();
            if c == 0 {
                continue;
            }
            for (dx, dy) in [(1, 0), (0, 1), (1, 1), (-1, 1)] {
                if cell(b, x + dx, y + dy) == Some(c) {
                    score += 6.0; // pairs set up future matches
                }
            }
        }
    }
    score
}

fn reachable(b: &Board, from: i32, to: i32, y: i32) -> bool {
    let (lo, hi) = if from < to { (from, to) } else { (to, from) };
    (lo..=hi).all(|x| column_top(b, x) >= y + 5)
}

/// Greedy search with one piece of lookahead (the "next" preview piece).
fn plan(b: &Board, cur_x: i32, cur_y: i32, piece: [u32; 3], next: [u32; 3]) -> (usize, i32) {
    let mut best = (f64::MIN, 0usize, cur_x);
    for x in X0..=X1 {
        if !reachable(b, cur_x, x, cur_y) {
            continue;
        }
        for r in 0..3 {
            let Some((nb, cleared, chains)) = place(b, x, rotate(piece, r)) else { continue };
            let mut follow = f64::MIN;
            for x2 in X0..=X1 {
                for r2 in 0..3 {
                    if let Some((nb2, c2, ch2)) = place(&nb, x2, rotate(next, r2)) {
                        follow = follow.max(c2 as f64 * 60.0 + ch2 as f64 * 40.0 + heuristic(&nb2));
                    }
                }
            }
            let value = cleared as f64 * 100.0 + chains as f64 * 80.0 + heuristic(&nb) + 0.5 * follow.max(-500.0)
                - r as f64 * 0.1
                - (x - cur_x).abs() as f64 * 0.1;
            if value > best.0 {
                best = (value, r, x);
            }
        }
    }
    (best.1, best.2)
}

// ---------------------------------------------------------------- director

#[derive(PartialEq, Debug, Clone, Copy)]
enum Phase {
    Play,
    Pausing { since: u64 },
    Lose,
}

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let asm_path = Path::new(args.get(1).expect("usage: saturn-capture <columns.asm> <out-dir>"));
    let out_dir = Path::new(args.get(2).expect("usage: saturn-capture <columns.asm> <out-dir>"));
    let difficulty = args.get(3).cloned().unwrap_or("2".into());
    let play_pieces: u32 = args.get(4).and_then(|s| s.parse().ok()).unwrap_or(30);
    // Human-ish pacing: one move every 4 frames, a soft drop every 3 (a frame is 16ms).
    let (move_every, drop_every) = (4u64, 3u64);
    let mut frame_no = 0u64;
    let pause_at_piece = play_pieces / 2;
    std::fs::create_dir_all(out_dir).unwrap();

    let source = std::fs::read_to_string(asm_path).unwrap();
    let path = asm_path.canonicalize().unwrap();
    let (binary, result) = assemble_text(&source, Some(path.to_str().unwrap()), Platform::Mips);
    let Some(binary) = binary else {
        if let AssemblerResult::Error { message, body, .. } = result {
            eprintln!("assembler error: {message}\n{}", body.unwrap_or_default());
        }
        std::process::exit(1);
    };
    let labels: HashMap<String, u32> = binary.labels.clone();
    let label = |name: &str| *labels.get(name).unwrap_or_else(|| panic!("missing label {name}"));
    let (a_x, a_y) = (label("cur_x"), label("cur_y"));
    let (a_c, a_side) = (label("colour1"), label("side_colour1"));
    println!("assembled OK: {} labels, entry {:#x}", labels.len(), binary.entry);

    let mut memory = SectionMemory::new();
    let keyboard: Arc<Mutex<KeyboardState>> = configure_keyboard(&mut memory);
    let mut cpu = state_from_binary(binary, 0x100000, memory, RawRegisters::default());
    setup_state(&mut cpu);
    let debugger = Executor::new(cpu, EmptyTracker {});

    let console_text = Arc::new(Mutex::new(String::new()));
    let midi_notes = Arc::new(AtomicUsize::new(0));
    let clock = Arc::new(VirtualClock(AtomicU64::new(0)));
    let state = Arc::new(Mutex::new(SyscallState::new(
        Box::new(Console(console_text.clone())),
        Box::new(Midi(midi_notes.clone())),
        clock.clone(),
        path.parent().map(|p| p.to_string_lossy().to_string()),
    )));
    // Answer the "Choose difficulty" prompt (syscall 5) like typing into Saturn's console.
    state.lock().unwrap().input_buffer.send(format!("{difficulty}\n").into_bytes());
    println!("> typed difficulty {difficulty}");

    let delegate = SyscallDelegate::new(state.clone());
    debugger.override_mode(ExecutorMode::Running);

    let mut frames = File::create(out_dir.join("frames.bin")).unwrap();
    let mut events = File::create(out_dir.join("events.txt")).unwrap();
    let mut ticks = File::create(out_dir.join("ticks.txt")).unwrap();
    let mut last_frame: Vec<u8> = vec![];
    let mut last_tick = u64::MAX;
    let mut last_y: Option<i32> = None;
    let mut pieces = 0u32;
    let mut keys: VecDeque<char> = VecDeque::new();
    let mut phase = Phase::Play;
    let mut paused_once = false;
    let press = |c: char, t: u64, events: &mut File| {
        let mut kb = keyboard.lock().unwrap();
        kb.push_key(c, false);
        kb.push_key(c, true);
        writeln!(events, "{t} key {c}").unwrap();
    };

    let outcome = loop {
        if let Some((frame, result)) = block_on(delegate.run_batch(&debugger, 20_000, false, false)) {
            break format!("{:?} / {:?}", frame.mode, result);
        }
        let t = clock.0.load(Ordering::SeqCst);
        if t == last_tick {
            continue;
        }
        last_tick = t;
        frame_no += 1;
        if t > 15 * 60 * 1000 {
            break "virtual time limit".into();
        }

        // --- snapshot the bitmap display
        let (pixels, words, vars, score) = debugger.with_state(|s| {
            let mut rgb = Vec::with_capacity((W * H * 3) as usize);
            let mut words = vec![0u32; (W * H) as usize];
            for i in 0..W * H {
                let v = s.memory.get_u32(DISPLAY + i * 4).unwrap_or(0);
                words[i as usize] = v & 0xFFFFFF;
                rgb.extend_from_slice(&[(v >> 16) as u8, (v >> 8) as u8, v as u8]);
            }
            let rd = |a: u32| s.memory.get_u32(a).unwrap_or(0);
            let vars = (
                rd(a_x) as i32,
                rd(a_y) as i32,
                [rd(a_c), rd(a_c + 4), rd(a_c + 8)],
                [rd(a_side), rd(a_side + 4), rd(a_side + 8)],
            );
            (rgb, words, vars, s.registers.raw().line[21])
        });
        if pixels != last_frame {
            frames.write_all(&(t as u32).to_le_bytes()).unwrap();
            frames.write_all(&pixels).unwrap();
            last_frame = pixels;
        }

        // --- drive the game
        let (cur_x, cur_y, piece, next) = vars;
        writeln!(ticks, "{t} {cur_x} {cur_y} {score}").unwrap();
        if let Phase::Pausing { since } = phase {
            if t >= since + 2500 {
                press('p', t, &mut events);
                writeln!(events, "{t} unpause").unwrap();
                phase = Phase::Play;
            }
            continue;
        }
        if piece == [0, 0, 0] || !(X0..=X1).contains(&cur_x) {
            continue; // not in the falling-piece loop yet
        }
        if words[(ROW / 4 + 1) as usize] != 0xD3D3D3 {
            continue; // end screen covers the walls: any key here restarts (is_r_pressed accepts any key)
        }
        let mut board: Board = [[0; 13]; 6];
        for x in X0..=X1 {
            for y in Y0..=Y1 {
                let falling = x == cur_x && (cur_y..cur_y + 3).contains(&y);
                if !falling {
                    set(&mut board, x, y, words[(y as u32 * (ROW / 4) + x as u32) as usize]);
                }
            }
        }

        let spawned = last_y.map_or(true, |ly| cur_y < ly);
        last_y = Some(cur_y);
        if spawned {
            pieces += 1;
            writeln!(events, "{t} spawn {pieces} score {score}").unwrap();
            keys.clear();
            if phase == Phase::Play && pieces > play_pieces {
                phase = Phase::Lose;
                writeln!(events, "{t} lose").unwrap();
            }
            if phase == Phase::Play && pieces == pause_at_piece && !paused_once {
                paused_once = true;
                press('p', t, &mut events);
                writeln!(events, "{t} pause").unwrap();
                phase = Phase::Pausing { since: t };
                continue;
            }
            let (rot, target) = match phase {
                Phase::Lose => (0, (X0..=X1).min_by_key(|&x| column_top(&board, x)).unwrap()),
                _ => plan(&board, cur_x, cur_y, piece, next),
            };
            keys.extend(std::iter::repeat('w').take(rot));
            let dir = if target > cur_x { 'd' } else { 'a' };
            keys.extend(std::iter::repeat(dir).take((target - cur_x).unsigned_abs() as usize));
        }

        // Only press when the piece can't land this frame, otherwise the key
        // would leak into the next piece (the landing frame skips keyboard_input).
        if cell(&board, cur_x, cur_y + 3) != Some(0) {
            continue;
        }
        if !keys.is_empty() {
            if frame_no % move_every == 0 {
                press(keys.pop_front().unwrap(), t, &mut events);
            }
        } else if frame_no % drop_every == 0 {
            press('s', t, &mut events);
        }
    };

    let console = console_text.lock().unwrap().clone();
    std::fs::write(out_dir.join("console.txt"), &console).unwrap();
    writeln!(events, "{} end {}", clock.0.load(Ordering::SeqCst), outcome).unwrap();
    println!();
    println!("program stopped: {outcome}");
    println!("virtual time: {} ms, pieces: {pieces}, midi notes requested: {}", clock.0.load(Ordering::SeqCst), midi_notes.load(Ordering::SeqCst));
}
