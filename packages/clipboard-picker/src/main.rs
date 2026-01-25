use std::env;
use std::io::Write;
use std::process::{Command, ExitStatus, Stdio};

fn main() {
    let cliphist = env::var("CLIPHIST_BIN").unwrap_or_else(|_| "cliphist".into());
    let rofi = env::var("ROFI_BIN").unwrap_or_else(|_| "rofi".into());
    let wl_copy = env::var("WL_COPY_BIN").unwrap_or_else(|_| "wl-copy".into());
    let wl_paste = env::var("WL_PASTE_BIN").unwrap_or_else(|_| "wl-paste".into());
    let zenity = env::var("ZENITY_BIN").unwrap_or_else(|_| "zenity".into());

    let current_hash = get_clipboard_hash(&wl_paste);
    let entries = get_marked_entries(&cliphist, &current_hash);

    if entries.is_empty() {
        eprintln!("No clipboard history");
        return;
    }

    let (selection, exit_code) = run_rofi(&rofi, &entries);

    if selection.is_empty() {
        return;
    }

    let clean_entry = clean_marker(&selection);

    match exit_code {
        0 => copy_entry(&cliphist, &wl_copy, &clean_entry),
        10 => quick_edit(&cliphist, &wl_copy, &zenity, &clean_entry),
        11 => open_in_editor(&cliphist, &clean_entry),
        12 => delete_entry(&cliphist, &clean_entry),
        _ => copy_entry(&cliphist, &wl_copy, &clean_entry),
    }
}

fn get_clipboard_hash(wl_paste: &str) -> String {
    Command::new(wl_paste)
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .output()
        .ok()
        .map(|out| {
            let content: String = String::from_utf8_lossy(&out.stdout).chars().take(1000).collect();
            simple_hash(&content)
        })
        .unwrap_or_default()
}

fn simple_hash(s: &str) -> String {
    let mut hash: u64 = 5381;
    for c in s.bytes() {
        hash = hash.wrapping_mul(33).wrapping_add(c as u64);
    }
    format!("{:x}", hash)
}

fn get_marked_entries(cliphist: &str, current_hash: &str) -> Vec<String> {
    let output = Command::new(cliphist)
        .arg("list")
        .stdout(Stdio::piped())
        .output()
        .expect("Failed to run cliphist list");

    String::from_utf8_lossy(&output.stdout)
        .lines()
        .map(|line| {
            let decoded = decode_entry(cliphist, line);
            let entry_hash = simple_hash(&decoded.chars().take(1000).collect::<String>());
            if entry_hash == current_hash {
                format!("► {}", line)
            } else {
                format!("  {}", line)
            }
        })
        .collect()
}

fn decode_entry(cliphist: &str, entry: &str) -> String {
    let mut child = Command::new(cliphist)
        .arg("decode")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .expect("Failed to spawn cliphist decode");

    if let Some(mut stdin) = child.stdin.take() {
        let _ = stdin.write_all(entry.as_bytes());
    }

    let output = child.wait_with_output().expect("Failed to read output");
    String::from_utf8_lossy(&output.stdout).to_string()
}

fn run_rofi(rofi: &str, entries: &[String]) -> (String, i32) {
    let input = entries.join("\n");

    let mut child = Command::new(rofi)
        .args([
            "-dmenu",
            "-i",
            "-p", "📋 Clipboard",
            "-mesg", "Enter=Copy | Alt+E=Edit | Alt+O=Open | Alt+D=Delete",
            "-kb-accept-entry", "Return,KP_Enter",
            "-kb-custom-1", "Alt+e",
            "-kb-custom-2", "Alt+o", 
            "-kb-custom-3", "Alt+d",
        ])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .expect("Failed to spawn rofi");

    if let Some(mut stdin) = child.stdin.take() {
        let _ = stdin.write_all(input.as_bytes());
    }

    let output = child.wait_with_output().expect("Failed to read rofi output");
    let exit_code = output.status.code().unwrap_or(1);
    let selection = String::from_utf8_lossy(&output.stdout).trim().to_string();

    (selection, exit_code)
}

fn clean_marker(entry: &str) -> String {
    entry
        .trim_start_matches("► ")
        .trim_start_matches("  ")
        .to_string()
}

fn copy_entry(cliphist: &str, wl_copy: &str, entry: &str) {
    let decoded = decode_entry(cliphist, entry);

    let mut child = Command::new(wl_copy)
        .stdin(Stdio::piped())
        .spawn()
        .expect("Failed to spawn wl-copy");

    if let Some(mut stdin) = child.stdin.take() {
        let _ = stdin.write_all(decoded.as_bytes());
    }

    let _ = child.wait();
}

fn quick_edit(cliphist: &str, wl_copy: &str, zenity: &str, entry: &str) {
    let content = decode_entry(cliphist, entry);

    let mut child = Command::new(zenity)
        .args([
            "--text-info",
            "--editable",
            "--title=Clipboard Editor",
            "--width=600",
            "--height=400",
            "--font=monospace 10",
        ])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .expect("Failed to spawn zenity");

    if let Some(mut stdin) = child.stdin.take() {
        let _ = stdin.write_all(content.as_bytes());
    }

    let output = child.wait_with_output().expect("Failed to read zenity output");
    let edited = String::from_utf8_lossy(&output.stdout);

    if !edited.is_empty() {
        let mut copy_child = Command::new(wl_copy)
            .stdin(Stdio::piped())
            .spawn()
            .expect("Failed to spawn wl-copy");

        if let Some(mut stdin) = copy_child.stdin.take() {
            let _ = stdin.write_all(edited.as_bytes());
        }

        let _ = copy_child.wait();
    }
}

fn delete_entry(cliphist: &str, entry: &str) {
    let mut child = Command::new(cliphist)
        .arg("delete")
        .stdin(Stdio::piped())
        .spawn()
        .expect("Failed to spawn cliphist delete");

    if let Some(mut stdin) = child.stdin.take() {
        let _ = stdin.write_all(entry.as_bytes());
    }

    let _ = child.wait();
}

fn open_in_editor(cliphist: &str, entry: &str) {
    let content = decode_entry(cliphist, entry);
    let tmpfile = format!("/tmp/clipboard-{}.txt", std::process::id());

    std::fs::write(&tmpfile, &content).expect("Failed to write temp file");

    let editors = ["xdg-open", "cosmic-edit", "kate", "kwrite", "gedit"];

    for editor in &editors {
        if Command::new("which")
            .arg(editor)
            .stdout(Stdio::null())
            .status()
            .map(|s| s.success())
            .unwrap_or(false)
        {
            let _ = Command::new(editor).arg(&tmpfile).spawn();

            std::thread::spawn(move || {
                std::thread::sleep(std::time::Duration::from_secs(300));
                let _ = std::fs::remove_file(&tmpfile);
            });

            return;
        }
    }
}
