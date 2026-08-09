use anyhow::{anyhow, bail, Context, Result};
use getrandom::getrandom;
use hkdf::Hkdf;
use rusqlite::{params, Connection, OpenFlags};
use sha2::{Digest, Sha256};
use std::env;
use std::fs;
use std::io::{self, Read, Write};
use std::os::unix::fs::{MetadataExt, PermissionsExt};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::Duration;
use unicode_segmentation::UnicodeSegmentation;
use zeroize::Zeroizing;

const VERSION: &str = env!("CARGO_PKG_VERSION");
const MAX_ITEMS: i64 = 200;
const MAX_DEDUPE_SEARCH: i64 = 100;
const MAX_STORE_BYTES: u64 = 5_000_000;
const PREVIEW_WIDTH: usize = 100;
const KEY_APPLICATION: &str = "cliphist";
const KEY_PURPOSE: &str = "history-master-key";
const KEY_LABEL: &str = "Encrypted clipboard history master key";
const HKDF_INFO: &[u8] = b"cliphist/sqlcipher/v1";

fn main() {
    if let Err(error) = run() {
        eprintln!("cliphist-secure: {error:#}");
        std::process::exit(1);
    }
}

fn run() -> Result<()> {
    harden_process()?;

    let mut args = env::args().skip(1);
    let command = args.next().ok_or_else(|| anyhow!(usage()))?;
    let remaining: Vec<String> = args.collect();

    match command.as_str() {
        "version" => {
            require_no_args(&remaining)?;
            print_version();
            return Ok(());
        }
        "capture" => {
            return capture_command(&remaining);
        }
        _ => {}
    }

    if command == "store" {
        require_no_args(&remaining)?;
        let clipboard_state = env::var("CLIPBOARD_STATE").ok();
        if clipboard_state.as_deref() == Some("sensitive") {
            return Ok(());
        }
        let paths = Paths::from_environment()?;
        match store_action(clipboard_state.as_deref(), paths.capture_paused()) {
            StoreAction::Skip => return Ok(()),
            StoreAction::Clear => {
                return with_database_at(&paths, |connection| delete_newest(connection));
            }
            StoreAction::Store => {}
        }

        let Some(content) = read_store_input()? else {
            return Ok(());
        };
        return with_database_at(&paths, |connection| store(connection, &content));
    }

    match command.as_str() {
        "init" => {
            require_no_args(&remaining)?;
            with_database(|connection| verify_integrity(connection))
        }
        "list" => {
            require_no_args(&remaining)?;
            with_database(|connection| list(connection, &mut io::stdout().lock()))
        }
        "decode" => {
            if remaining.len() > 1 {
                bail!(usage());
            }
            let selector = match remaining.first() {
                Some(value) => value.clone(),
                None => read_stdin_to_string()?,
            };
            with_database(|connection| decode(connection, &selector, &mut io::stdout().lock()))
        }
        "delete" => {
            require_no_args(&remaining)?;
            let selectors = read_stdin_to_string()?;
            with_database(|connection| delete(connection, &selectors))
        }
        "delete-query" => {
            if remaining.len() != 1 {
                bail!("delete-query requires exactly one query argument");
            }
            with_database(|connection| delete_query(connection, &remaining[0]))
        }
        "wipe" => {
            require_no_args(&remaining)?;
            with_database(wipe)
        }
        _ => bail!(usage()),
    }
}

fn usage() -> &'static str {
    "usage:\n  cliphist init|store|list|decode|delete|delete-query|wipe|version\n  cliphist capture pause|resume|status"
}

fn require_no_args(args: &[String]) -> Result<()> {
    if args.is_empty() {
        Ok(())
    } else {
        bail!(usage())
    }
}

#[derive(Debug, Eq, PartialEq)]
enum StoreAction {
    Skip,
    Clear,
    Store,
}

fn store_action(clipboard_state: Option<&str>, paused: bool) -> StoreAction {
    match clipboard_state {
        Some("sensitive") => StoreAction::Skip,
        Some("clear") => StoreAction::Clear,
        _ if paused => StoreAction::Skip,
        _ => StoreAction::Store,
    }
}

fn print_version() {
    println!("version\t{VERSION}");
    println!("max-items\t{MAX_ITEMS}");
    println!("max-dedupe-search\t{MAX_DEDUPE_SEARCH}");
    println!("preview-width\t{PREVIEW_WIDTH}");
}

fn harden_process() -> Result<()> {
    unsafe {
        libc::umask(0o077);
        if libc::prctl(libc::PR_SET_DUMPABLE, 0, 0, 0, 0) != 0 {
            return Err(io::Error::last_os_error()).context("disable process dumps");
        }
    }
    Ok(())
}

#[derive(Debug)]
struct Paths {
    state_root: PathBuf,
    database: PathBuf,
    runtime_root: PathBuf,
    control_dir: PathBuf,
    paused_file: PathBuf,
}

impl Paths {
    fn from_environment() -> Result<Self> {
        let home = absolute_environment_path("HOME")?;
        let state_home = match env::var_os("XDG_STATE_HOME") {
            Some(path) if !path.is_empty() => {
                require_absolute(PathBuf::from(path), "XDG_STATE_HOME")?
            }
            _ => home.join(".local/state"),
        };
        let runtime_home = absolute_environment_path("XDG_RUNTIME_DIR")?;
        if !runtime_home.is_dir() {
            bail!(
                "runtime directory does not exist: {}",
                runtime_home.display()
            );
        }

        let state_root = state_home.join("cliphist-vault");
        let runtime_root = runtime_home.join("cliphist-vault");
        Ok(Self {
            database: state_root.join("history.sqlite3"),
            control_dir: runtime_root.join("control"),
            paused_file: runtime_root.join("control/capture-paused"),
            state_root,
            runtime_root,
        })
    }

    fn prepare_state(&self) -> Result<()> {
        secure_directory(&self.state_root)
    }

    fn prepare_runtime(&self) -> Result<()> {
        secure_directory(&self.runtime_root)
    }

    fn prepare_control(&self) -> Result<()> {
        self.prepare_runtime()?;
        secure_directory(&self.control_dir)
    }

    fn capture_paused(&self) -> bool {
        self.paused_file.exists()
    }
}

fn absolute_environment_path(name: &str) -> Result<PathBuf> {
    let value = env::var_os(name).ok_or_else(|| anyhow!("{name} is not set"))?;
    if value.is_empty() {
        bail!("{name} is empty");
    }
    require_absolute(PathBuf::from(value), name)
}

fn require_absolute(path: PathBuf, name: &str) -> Result<PathBuf> {
    if !path.is_absolute() {
        bail!("{name} must be an absolute path");
    }
    Ok(path)
}

fn secure_directory(path: &Path) -> Result<()> {
    if path.try_exists().context("inspect secure directory")? {
        let metadata = fs::symlink_metadata(path)
            .with_context(|| format!("inspect directory {}", path.display()))?;
        if metadata.file_type().is_symlink() {
            bail!("refusing symlinked directory: {}", path.display());
        }
        if !metadata.is_dir() {
            bail!("secure path is not a directory: {}", path.display());
        }
        ensure_owned_by_current_user(path, &metadata)?;
    } else {
        fs::create_dir_all(path).with_context(|| format!("create directory {}", path.display()))?;
    }

    fs::set_permissions(path, fs::Permissions::from_mode(0o700))
        .with_context(|| format!("set directory permissions on {}", path.display()))?;
    Ok(())
}

fn ensure_owned_by_current_user(path: &Path, metadata: &fs::Metadata) -> Result<()> {
    let uid = unsafe { libc::geteuid() };
    if metadata.uid() != uid {
        bail!(
            "path is owned by uid {}, expected uid {}: {}",
            metadata.uid(),
            uid,
            path.display()
        );
    }
    Ok(())
}

fn secure_database_files(database: &Path) -> Result<()> {
    let mut paths = vec![database.to_path_buf()];
    paths.push(PathBuf::from(format!("{}-wal", database.display())));
    paths.push(PathBuf::from(format!("{}-shm", database.display())));

    for path in paths {
        if !path.try_exists().context("inspect database file")? {
            continue;
        }
        let metadata = fs::symlink_metadata(&path)
            .with_context(|| format!("inspect database file {}", path.display()))?;
        if metadata.file_type().is_symlink() || !metadata.is_file() {
            bail!("refusing unsafe database file: {}", path.display());
        }
        ensure_owned_by_current_user(&path, &metadata)?;
        fs::set_permissions(&path, fs::Permissions::from_mode(0o600))
            .with_context(|| format!("set database permissions on {}", path.display()))?;
    }
    Ok(())
}

trait KeyProvider {
    fn lookup(&self) -> Result<Option<Zeroizing<Vec<u8>>>>;
    fn store(&self, key: &[u8]) -> Result<()>;
}

struct SecretServiceKeyProvider;

impl SecretServiceKeyProvider {
    fn executable() -> &'static str {
        option_env!("CLIPHIST_SECRET_TOOL").unwrap_or("secret-tool")
    }
}

impl KeyProvider for SecretServiceKeyProvider {
    fn lookup(&self) -> Result<Option<Zeroizing<Vec<u8>>>> {
        let output = Command::new(Self::executable())
            .args([
                "lookup",
                "application",
                KEY_APPLICATION,
                "purpose",
                KEY_PURPOSE,
            ])
            .stderr(Stdio::null())
            .output()
            .context("query GNOME Keyring")?;

        if !output.status.success() {
            return Ok(None);
        }

        let stdout = Zeroizing::new(output.stdout);
        let text = Zeroizing::new(
            String::from_utf8(stdout.to_vec()).context("GNOME Keyring returned non-UTF-8 data")?,
        );
        decode_master_key(text.trim()).map(Some)
    }

    fn store(&self, key: &[u8]) -> Result<()> {
        let encoded = Zeroizing::new(hex::encode(key));
        let mut child = Command::new(Self::executable())
            .args([
                "store",
                &format!("--label={KEY_LABEL}"),
                "application",
                KEY_APPLICATION,
                "purpose",
                KEY_PURPOSE,
            ])
            .stdin(Stdio::piped())
            .stdout(Stdio::null())
            .spawn()
            .context("start GNOME Keyring storage")?;

        {
            let mut stdin = child
                .stdin
                .take()
                .ok_or_else(|| anyhow!("GNOME Keyring stdin is unavailable"))?;
            stdin
                .write_all(encoded.as_bytes())
                .context("write key to GNOME Keyring")?;
            stdin.write_all(b"\n").context("finish Keyring input")?;
        }

        let status = child.wait().context("wait for GNOME Keyring storage")?;
        if !status.success() {
            bail!("GNOME Keyring rejected the clipboard master key");
        }
        Ok(())
    }
}

fn decode_master_key(encoded: &str) -> Result<Zeroizing<Vec<u8>>> {
    if encoded.len() != 64 || !encoded.bytes().all(|byte| byte.is_ascii_hexdigit()) {
        bail!("GNOME Keyring returned an invalid clipboard master key");
    }
    let decoded = Zeroizing::new(hex::decode(encoded).context("decode clipboard master key")?);
    if decoded.len() != 32 {
        bail!("GNOME Keyring returned an invalid clipboard master key length");
    }
    Ok(decoded)
}

fn get_or_create_master_key<P: KeyProvider>(
    provider: &P,
    database_exists: bool,
) -> Result<Zeroizing<Vec<u8>>> {
    if let Some(key) = provider.lookup()? {
        return Ok(key);
    }
    if database_exists {
        bail!("encrypted history exists but its GNOME Keyring master key is unavailable");
    }

    let mut generated = Zeroizing::new(vec![0_u8; 32]);
    getrandom(&mut generated).map_err(|error| anyhow!("generate clipboard master key: {error}"))?;
    provider.store(&generated)?;

    let retrieved = provider
        .lookup()?
        .ok_or_else(|| anyhow!("GNOME Keyring did not return the stored clipboard master key"))?;
    if generated.as_slice() != retrieved.as_slice() {
        bail!("GNOME Keyring returned a different clipboard master key after storage");
    }
    Ok(retrieved)
}

fn derive_database_key(master_key: &[u8]) -> Result<Zeroizing<Vec<u8>>> {
    let hkdf = Hkdf::<Sha256>::new(None, master_key);
    let mut derived = Zeroizing::new(vec![0_u8; 32]);
    hkdf.expand(HKDF_INFO, &mut derived)
        .map_err(|_| anyhow!("derive SQLCipher key"))?;
    Ok(derived)
}

fn with_database<T>(operation: impl FnOnce(&mut Connection) -> Result<T>) -> Result<T> {
    let paths = Paths::from_environment()?;
    with_database_at(&paths, operation)
}

fn with_database_at<T>(
    paths: &Paths,
    operation: impl FnOnce(&mut Connection) -> Result<T>,
) -> Result<T> {
    paths.prepare_state()?;
    let database_exists = paths
        .database
        .try_exists()
        .context("inspect encrypted history")?;
    if database_exists {
        reject_symlink(&paths.database)?;
    }

    let provider = SecretServiceKeyProvider;
    let master_key = get_or_create_master_key(&provider, database_exists)?;
    let database_key = derive_database_key(&master_key)?;
    let mut connection = open_database(&paths.database, &database_key)?;
    let result = operation(&mut connection);
    secure_database_files(&paths.database)?;
    result
}

fn reject_symlink(path: &Path) -> Result<()> {
    let metadata =
        fs::symlink_metadata(path).with_context(|| format!("inspect path {}", path.display()))?;
    if metadata.file_type().is_symlink() {
        bail!("refusing symlinked database: {}", path.display());
    }
    if !metadata.is_file() {
        bail!("database path is not a regular file: {}", path.display());
    }
    ensure_owned_by_current_user(path, &metadata)
}

fn open_database(path: &Path, key: &[u8]) -> Result<Connection> {
    let flags = OpenFlags::SQLITE_OPEN_READ_WRITE
        | OpenFlags::SQLITE_OPEN_CREATE
        | OpenFlags::SQLITE_OPEN_NO_MUTEX;
    let connection = Connection::open_with_flags(path, flags)
        .with_context(|| format!("open encrypted database {}", path.display()))?;

    let encoded_key = Zeroizing::new(hex::encode(key));
    let key_pragma = Zeroizing::new(format!("PRAGMA key = \"x'{}'\";", encoded_key.as_str()));
    connection
        .execute_batch(&key_pragma)
        .context("apply SQLCipher key")?;

    let cipher_version: String = connection
        .query_row("PRAGMA cipher_version;", [], |row| row.get(0))
        .context("SQLCipher support is unavailable")?;
    if cipher_version.trim().is_empty() {
        bail!("SQLCipher support is unavailable");
    }

    connection
        .query_row("SELECT count(*) FROM sqlite_master;", [], |row| {
            row.get::<_, i64>(0)
        })
        .context("validate encrypted database key")?;
    connection
        .busy_timeout(Duration::from_secs(2))
        .context("configure database busy timeout")?;
    connection
        .execute_batch(
            "PRAGMA cipher_memory_security = ON;
             PRAGMA temp_store = MEMORY;
             PRAGMA secure_delete = ON;
             PRAGMA synchronous = FULL;",
        )
        .context("configure encrypted database")?;

    let journal_mode: String = connection
        .query_row("PRAGMA journal_mode = WAL;", [], |row| row.get(0))
        .context("enable encrypted WAL journal")?;
    if !journal_mode.eq_ignore_ascii_case("wal") {
        bail!("failed to enable encrypted WAL journal");
    }

    connection
        .execute_batch(
            "CREATE TABLE IF NOT EXISTS entries (
                 id INTEGER PRIMARY KEY AUTOINCREMENT,
                 content TEXT NOT NULL,
                 content_hash BLOB NOT NULL,
                 created_at INTEGER NOT NULL DEFAULT (unixepoch())
             );
             CREATE INDEX IF NOT EXISTS entries_content_hash_idx
                 ON entries(content_hash);",
        )
        .context("initialize encrypted history schema")?;
    secure_database_files(path)?;
    Ok(connection)
}

fn verify_integrity(connection: &Connection) -> Result<()> {
    let result: String = connection
        .query_row("PRAGMA integrity_check;", [], |row| row.get(0))
        .context("check encrypted database integrity")?;
    if result != "ok" {
        bail!("encrypted database integrity check failed: {result}");
    }
    Ok(())
}

fn read_store_input() -> Result<Option<String>> {
    let mut input = Vec::new();
    io::stdin()
        .take(MAX_STORE_BYTES + 1)
        .read_to_end(&mut input)
        .context("read clipboard input")?;
    if input.len() as u64 > MAX_STORE_BYTES {
        return Ok(None);
    }
    let content = String::from_utf8(input).context("clipboard input is not valid UTF-8")?;
    if content.trim().is_empty() {
        return Ok(None);
    }
    Ok(Some(content))
}

fn read_stdin_to_string() -> Result<String> {
    let mut input = String::new();
    io::stdin()
        .read_to_string(&mut input)
        .context("read command input")?;
    Ok(input)
}

fn store(connection: &mut Connection, content: &str) -> Result<()> {
    let hash = Sha256::digest(content.as_bytes());
    let transaction = connection
        .transaction()
        .context("begin store transaction")?;

    let duplicate_ids = {
        let mut statement = transaction
            .prepare("SELECT id, content FROM entries ORDER BY id DESC LIMIT ?1")
            .context("prepare duplicate search")?;
        let candidates = statement
            .query_map(params![MAX_DEDUPE_SEARCH + 1], |row| {
                Ok((row.get::<_, i64>(0)?, row.get::<_, String>(1)?))
            })
            .context("search recent clipboard entries")?;
        let mut ids = Vec::new();
        for candidate in candidates {
            let (id, existing) = candidate.context("read duplicate candidate")?;
            if existing == content {
                ids.push(id);
            }
        }
        ids
    };

    for id in duplicate_ids {
        transaction
            .execute("DELETE FROM entries WHERE id = ?1", params![id])
            .context("delete duplicate clipboard entry")?;
    }
    transaction
        .execute(
            "INSERT INTO entries(content, content_hash) VALUES (?1, ?2)",
            params![content, hash.as_slice()],
        )
        .context("insert clipboard entry")?;
    transaction
        .execute(
            "DELETE FROM entries
             WHERE id NOT IN (
                 SELECT id FROM entries ORDER BY id DESC LIMIT ?1
             )",
            params![MAX_ITEMS],
        )
        .context("enforce clipboard retention limit")?;
    transaction.commit().context("commit clipboard entry")?;
    Ok(())
}

fn list(connection: &Connection, output: &mut dyn Write) -> Result<()> {
    let mut statement = connection
        .prepare("SELECT id, content FROM entries ORDER BY id DESC")
        .context("prepare clipboard history listing")?;
    let rows = statement
        .query_map([], |row| {
            Ok((row.get::<_, i64>(0)?, row.get::<_, String>(1)?))
        })
        .context("query clipboard history")?;

    for row in rows {
        let (id, content) = row.context("read clipboard history entry")?;
        writeln!(output, "{id}\t{}", preview(&content)).context("write clipboard history")?;
    }
    Ok(())
}

fn preview(content: &str) -> String {
    let flattened = content.split_whitespace().collect::<Vec<_>>().join(" ");
    let mut graphemes = flattened.graphemes(true);
    let preview = graphemes.by_ref().take(PREVIEW_WIDTH).collect::<String>();
    if graphemes.next().is_some() {
        format!("{preview}…")
    } else {
        preview
    }
}

fn extract_id(selector: &str) -> Result<i64> {
    let id = selector
        .split_once('\t')
        .map_or(selector, |(id, _)| id)
        .trim()
        .parse::<i64>()
        .context("clipboard selection is not prefixed with a numeric id")?;
    if id <= 0 {
        bail!("clipboard selection id must be positive");
    }
    Ok(id)
}

fn decode(connection: &Connection, selector: &str, output: &mut dyn Write) -> Result<()> {
    let id = extract_id(selector)?;
    let content: String = connection
        .query_row(
            "SELECT content FROM entries WHERE id = ?1",
            params![id],
            |row| row.get(0),
        )
        .with_context(|| format!("clipboard entry {id} was not found"))?;
    output
        .write_all(content.as_bytes())
        .context("write decoded clipboard entry")?;
    Ok(())
}

fn delete(connection: &mut Connection, selectors: &str) -> Result<()> {
    let ids = selectors
        .lines()
        .filter(|line| !line.trim().is_empty())
        .map(extract_id)
        .collect::<Result<Vec<_>>>()?;
    let transaction = connection
        .transaction()
        .context("begin delete transaction")?;
    for id in ids {
        transaction
            .execute("DELETE FROM entries WHERE id = ?1", params![id])
            .with_context(|| format!("delete clipboard entry {id}"))?;
    }
    transaction.commit().context("commit clipboard deletion")?;
    Ok(())
}

fn delete_query(connection: &Connection, query: &str) -> Result<()> {
    if query.is_empty() {
        bail!("please provide a query");
    }
    connection
        .execute(
            "DELETE FROM entries WHERE instr(content, ?1) > 0",
            params![query],
        )
        .context("delete clipboard entries matching query")?;
    Ok(())
}

fn delete_newest(connection: &Connection) -> Result<()> {
    connection
        .execute(
            "DELETE FROM entries WHERE id = (SELECT max(id) FROM entries)",
            [],
        )
        .context("delete newest clipboard entry")?;
    Ok(())
}

fn wipe(connection: &mut Connection) -> Result<()> {
    connection
        .execute_batch(
            "DELETE FROM entries;
             DELETE FROM sqlite_sequence WHERE name = 'entries';
             PRAGMA wal_checkpoint(TRUNCATE);
             VACUUM;",
        )
        .context("wipe encrypted clipboard history")?;
    Ok(())
}

fn capture_command(args: &[String]) -> Result<()> {
    if args.len() != 1 {
        bail!(usage());
    }
    let paths = Paths::from_environment()?;
    match args[0].as_str() {
        "pause" => {
            paths.prepare_control()?;
            reject_existing_symlink(&paths.paused_file)?;
            fs::write(&paths.paused_file, [])
                .with_context(|| format!("create {}", paths.paused_file.display()))?;
            fs::set_permissions(&paths.paused_file, fs::Permissions::from_mode(0o600))
                .context("secure capture pause marker")?;
        }
        "resume" => match fs::remove_file(&paths.paused_file) {
            Ok(()) => {}
            Err(error) if error.kind() == io::ErrorKind::NotFound => {}
            Err(error) => return Err(error).context("remove capture pause marker"),
        },
        "status" => {
            if paths.capture_paused() {
                println!("paused");
            } else {
                println!("active");
            }
        }
        _ => bail!(usage()),
    }
    Ok(())
}

fn reject_existing_symlink(path: &Path) -> Result<()> {
    match fs::symlink_metadata(path) {
        Ok(metadata) if metadata.file_type().is_symlink() => {
            bail!("refusing symlinked control file: {}", path.display())
        }
        Ok(metadata) if !metadata.is_file() => {
            bail!("control path is not a regular file: {}", path.display())
        }
        Ok(metadata) => ensure_owned_by_current_user(path, &metadata),
        Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(()),
        Err(error) => Err(error).context("inspect capture control file"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::RefCell;
    use tempfile::TempDir;

    fn test_key(byte: u8) -> Zeroizing<Vec<u8>> {
        Zeroizing::new(vec![byte; 32])
    }

    fn open_test_database(directory: &TempDir, key: &[u8]) -> (PathBuf, Connection) {
        let path = directory.path().join("history.sqlite3");
        secure_directory(directory.path()).unwrap();
        let connection = open_database(&path, key).unwrap();
        (path, connection)
    }

    #[test]
    fn sqlcipher_encrypts_database_and_rejects_wrong_key() {
        let directory = TempDir::new().unwrap();
        let key = test_key(0x41);
        let (path, mut connection) = open_test_database(&directory, &key);
        let secret = "unique-plaintext-clipboard-secret";
        store(&mut connection, secret).unwrap();
        verify_integrity(&connection).unwrap();
        assert_encrypted_files(&path, secret);
        drop(connection);

        assert_encrypted_files(&path, secret);
        assert!(open_database(&path, &test_key(0x42)).is_err());

        let connection = open_database(&path, &key).unwrap();
        let version: String = connection
            .query_row("PRAGMA cipher_version;", [], |row| row.get(0))
            .unwrap();
        assert!(!version.trim().is_empty());
    }

    #[test]
    fn store_deduplicates_and_limits_history() {
        let directory = TempDir::new().unwrap();
        let (_path, mut connection) = open_test_database(&directory, &test_key(1));
        store(&mut connection, "duplicate").unwrap();
        store(&mut connection, "other").unwrap();
        store(&mut connection, "duplicate").unwrap();

        let duplicate_count: i64 = connection
            .query_row(
                "SELECT count(*) FROM entries WHERE content = 'duplicate'",
                [],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(duplicate_count, 1);

        for index in 0..250 {
            store(&mut connection, &format!("entry-{index}")).unwrap();
        }
        let count: i64 = connection
            .query_row("SELECT count(*) FROM entries", [], |row| row.get(0))
            .unwrap();
        assert_eq!(count, MAX_ITEMS);
    }

    #[test]
    fn list_decode_delete_clear_query_and_wipe_work() {
        let directory = TempDir::new().unwrap();
        let (_path, mut connection) = open_test_database(&directory, &test_key(2));
        store(&mut connection, "first line\nsecond line").unwrap();
        store(&mut connection, "delete me").unwrap();

        let mut listing = Vec::new();
        list(&connection, &mut listing).unwrap();
        let listing = String::from_utf8(listing).unwrap();
        let rows: Vec<&str> = listing.lines().collect();
        assert_eq!(rows.len(), 2);
        assert!(rows[0].ends_with("\tdelete me"));
        assert!(rows[1].ends_with("\tfirst line second line"));

        let mut decoded = Vec::new();
        decode(&connection, rows[1], &mut decoded).unwrap();
        assert_eq!(decoded, b"first line\nsecond line");

        delete(&mut connection, rows[1]).unwrap();
        delete_query(&connection, "delete").unwrap();
        assert_eq!(entry_count(&connection), 0);

        store(&mut connection, "one").unwrap();
        store(&mut connection, "two").unwrap();
        delete_newest(&connection).unwrap();
        assert_eq!(entry_count(&connection), 1);
        wipe(&mut connection).unwrap();
        assert_eq!(entry_count(&connection), 0);
    }

    #[test]
    fn sensitive_and_paused_capture_are_skipped() {
        assert_eq!(store_action(Some("sensitive"), false), StoreAction::Skip);
        assert_eq!(store_action(Some("sensitive"), true), StoreAction::Skip);
        assert_eq!(store_action(None, true), StoreAction::Skip);
        assert_eq!(store_action(Some("clear"), true), StoreAction::Clear);
        assert_eq!(store_action(None, false), StoreAction::Store);
    }

    #[test]
    fn preview_is_flat_unicode_safe_and_bounded() {
        assert_eq!(preview("  a\tb\n c  "), "a b c");
        let long = "🦀".repeat(PREVIEW_WIDTH + 1);
        let rendered = preview(&long);
        assert_eq!(rendered.graphemes(true).count(), PREVIEW_WIDTH + 1);
        assert!(rendered.ends_with('…'));
    }

    #[test]
    fn database_and_directory_permissions_are_private() {
        let directory = TempDir::new().unwrap();
        let (path, connection) = open_test_database(&directory, &test_key(3));
        secure_database_files(&path).unwrap();
        assert_eq!(
            fs::metadata(directory.path()).unwrap().mode() & 0o777,
            0o700
        );
        assert_eq!(fs::metadata(path).unwrap().mode() & 0o777, 0o600);
        drop(connection);
    }

    #[derive(Default)]
    struct MockKeyProvider {
        key: RefCell<Option<Vec<u8>>>,
        fail_store: bool,
    }

    impl KeyProvider for MockKeyProvider {
        fn lookup(&self) -> Result<Option<Zeroizing<Vec<u8>>>> {
            Ok(self.key.borrow().clone().map(Zeroizing::new))
        }

        fn store(&self, key: &[u8]) -> Result<()> {
            if self.fail_store {
                bail!("mock keyring is locked");
            }
            *self.key.borrow_mut() = Some(key.to_vec());
            Ok(())
        }
    }

    #[test]
    fn key_provider_creates_once_and_fails_closed_for_existing_history() {
        let provider = MockKeyProvider::default();
        let first = get_or_create_master_key(&provider, false).unwrap();
        let second = get_or_create_master_key(&provider, true).unwrap();
        assert_eq!(first.as_slice(), second.as_slice());

        let unavailable = MockKeyProvider::default();
        assert!(get_or_create_master_key(&unavailable, true).is_err());

        let locked = MockKeyProvider {
            fail_store: true,
            ..MockKeyProvider::default()
        };
        assert!(get_or_create_master_key(&locked, false).is_err());
    }

    #[test]
    fn master_key_validation_and_derivation_are_stable() {
        assert!(decode_master_key("not-a-key").is_err());
        let master = decode_master_key(&"ab".repeat(32)).unwrap();
        let first = derive_database_key(&master).unwrap();
        let second = derive_database_key(&master).unwrap();
        assert_eq!(first.as_slice(), second.as_slice());
        assert_ne!(first.as_slice(), master.as_slice());
    }

    fn assert_encrypted_files(database: &Path, secret: &str) {
        for path in [
            database.to_path_buf(),
            PathBuf::from(format!("{}-wal", database.display())),
            PathBuf::from(format!("{}-shm", database.display())),
        ] {
            if !path.exists() {
                continue;
            }
            let bytes = fs::read(&path).unwrap();
            assert!(!bytes.starts_with(b"SQLite format 3\0"));
            assert!(!bytes
                .windows(secret.len())
                .any(|window| window == secret.as_bytes()));
        }
    }

    fn entry_count(connection: &Connection) -> i64 {
        connection
            .query_row("SELECT count(*) FROM entries", [], |row| row.get(0))
            .unwrap()
    }
}
