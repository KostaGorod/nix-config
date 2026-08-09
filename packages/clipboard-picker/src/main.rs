use std::env;
use std::io::Write;
use std::process::{Command, Output, Stdio};

fn main() {
    let cliphist = env::var("CLIPHIST_BIN").unwrap_or_else(|_| "cliphist".into());
    let rofi = env::var("ROFI_BIN").unwrap_or_else(|_| "rofi".into());
    let wl_copy = env::var("WL_COPY_BIN").unwrap_or_else(|_| "wl-copy".into());
    let zenity = env::var("ZENITY_BIN").unwrap_or_else(|_| "zenity".into());

    if let Err(error) = run(&cliphist, &rofi, &wl_copy, &zenity) {
        eprintln!("clipboard-picker: {error}");
        show_error(&zenity, &error);
    }
}

fn run(cliphist: &str, rofi: &str, wl_copy: &str, zenity: &str) -> Result<(), String> {
    let entries = get_entries(cliphist)?;
    if entries.is_empty() {
        show_empty(zenity);
        return Ok(());
    }

    let (selection, exit_code) = run_rofi(rofi, &entries)?;
    if selection.is_empty() {
        return Ok(());
    }

    match exit_code {
        0 => copy_entry(cliphist, wl_copy, &selection),
        10 => quick_edit(cliphist, wl_copy, zenity, &selection),
        11 => delete_entry(cliphist, &selection),
        1 => Ok(()),
        code => Err(format!(
            "clipboard menu exited unexpectedly with status {code}"
        )),
    }
}

fn get_entries(cliphist: &str) -> Result<Vec<String>, String> {
    let output = Command::new(cliphist)
        .arg("list")
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .output()
        .map_err(|error| format!("failed to start encrypted clipboard history: {error}"))?;
    require_success("load encrypted clipboard history", &output)?;

    Ok(String::from_utf8_lossy(&output.stdout)
        .lines()
        .map(str::to_owned)
        .collect())
}

fn decode_entry(cliphist: &str, entry: &str) -> Result<Vec<u8>, String> {
    let mut child = Command::new(cliphist)
        .arg("decode")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|error| format!("failed to start clipboard decryption: {error}"))?;

    child
        .stdin
        .take()
        .ok_or_else(|| "clipboard decryption stdin is unavailable".to_string())?
        .write_all(entry.as_bytes())
        .map_err(|error| format!("failed to select clipboard entry: {error}"))?;

    let output = child
        .wait_with_output()
        .map_err(|error| format!("failed to read decrypted clipboard entry: {error}"))?;
    require_success("decrypt clipboard entry", &output)?;
    Ok(output.stdout)
}

fn run_rofi(rofi: &str, entries: &[String]) -> Result<(String, i32), String> {
    let input = entries.join("\n");
    let mut child = Command::new(rofi)
        .args([
            "-dmenu",
            "-i",
            "-p",
            "📋 Clipboard",
            "-mesg",
            "Enter=Copy | Alt+E=Edit | Alt+D=Delete",
            "-kb-accept-entry",
            "Return,KP_Enter",
            "-kb-custom-1",
            "Alt+e",
            "-kb-custom-2",
            "Alt+d",
        ])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|error| format!("failed to open clipboard menu: {error}"))?;

    child
        .stdin
        .take()
        .ok_or_else(|| "clipboard menu stdin is unavailable".to_string())?
        .write_all(input.as_bytes())
        .map_err(|error| format!("failed to populate clipboard menu: {error}"))?;

    let output = child
        .wait_with_output()
        .map_err(|error| format!("failed to read clipboard menu selection: {error}"))?;
    let exit_code = output.status.code().unwrap_or(1);
    let selection = String::from_utf8_lossy(&output.stdout).trim().to_string();
    Ok((selection, exit_code))
}

fn copy_entry(cliphist: &str, wl_copy: &str, entry: &str) -> Result<(), String> {
    let decoded = decode_entry(cliphist, entry)?;
    copy_bytes(wl_copy, &decoded)
}

fn copy_bytes(wl_copy: &str, content: &[u8]) -> Result<(), String> {
    let mut child = Command::new(wl_copy)
        .stdin(Stdio::piped())
        .stdout(Stdio::null())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|error| format!("failed to start wl-copy: {error}"))?;

    child
        .stdin
        .take()
        .ok_or_else(|| "wl-copy stdin is unavailable".to_string())?
        .write_all(content)
        .map_err(|error| format!("failed to write clipboard content: {error}"))?;

    let output = child
        .wait_with_output()
        .map_err(|error| format!("failed to finish copying clipboard content: {error}"))?;
    require_success("copy clipboard entry", &output)
}

fn quick_edit(cliphist: &str, wl_copy: &str, zenity: &str, entry: &str) -> Result<(), String> {
    let content = decode_entry(cliphist, entry)?;
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
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|error| format!("failed to open clipboard editor: {error}"))?;

    child
        .stdin
        .take()
        .ok_or_else(|| "clipboard editor stdin is unavailable".to_string())?
        .write_all(&content)
        .map_err(|error| format!("failed to populate clipboard editor: {error}"))?;

    let output = child
        .wait_with_output()
        .map_err(|error| format!("failed to read clipboard editor: {error}"))?;
    if output.status.success() && !output.stdout.is_empty() {
        copy_bytes(wl_copy, &output.stdout)?;
    } else if output.status.code() != Some(1) && !output.status.success() {
        require_success("edit clipboard entry", &output)?;
    }
    Ok(())
}

fn delete_entry(cliphist: &str, entry: &str) -> Result<(), String> {
    let mut child = Command::new(cliphist)
        .arg("delete")
        .stdin(Stdio::piped())
        .stdout(Stdio::null())
        .stderr(Stdio::piped())
        .spawn()
        .map_err(|error| format!("failed to start clipboard deletion: {error}"))?;

    child
        .stdin
        .take()
        .ok_or_else(|| "clipboard deletion stdin is unavailable".to_string())?
        .write_all(entry.as_bytes())
        .map_err(|error| format!("failed to select clipboard entry for deletion: {error}"))?;

    let output = child
        .wait_with_output()
        .map_err(|error| format!("failed to finish clipboard deletion: {error}"))?;
    require_success("delete clipboard entry", &output)
}

fn require_success(action: &str, output: &Output) -> Result<(), String> {
    if output.status.success() {
        return Ok(());
    }
    let detail = String::from_utf8_lossy(&output.stderr).trim().to_string();
    if detail.is_empty() {
        Err(format!(
            "failed to {action} (status {})",
            output.status.code().unwrap_or(1)
        ))
    } else {
        Err(format!("failed to {action}: {detail}"))
    }
}

fn show_empty(zenity: &str) {
    let _ = Command::new(zenity)
        .args([
            "--info",
            "--title=Clipboard History",
            "--text=Clipboard history is empty.",
        ])
        .status();
}

fn show_error(zenity: &str, message: &str) {
    let _ = Command::new(zenity)
        .args(["--error", "--title=Clipboard History Error"])
        .arg(format!("--text={message}"))
        .status();
}
