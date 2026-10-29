use std::{collections::HashMap, sync::Arc, time::Duration};

use microsandbox::sandbox::SandboxHandle;
use microsandbox::{
    LocalBackend, Sandbox, SandboxMetricsReport, SandboxMetricsState,
    all_sandbox_metrics_reports_local, with_backend,
};
use serde::Serialize;

const MAX_ROWS: usize = 500;
type Result<T> = std::result::Result<T, Box<dyn std::error::Error + Send + Sync>>;

#[derive(Debug, PartialEq)]
enum Request {
    Status,
    Action {
        verb: String,
        name: String,
        id: String,
    },
}

fn request(args: &[String]) -> Result<Request> {
    match args {
        [verb] if verb == "status" => Ok(Request::Status),
        [verb, name, id]
            if ["start", "stop", "remove", "shell", "logs"].contains(&verb.as_str()) =>
        {
            if name.is_empty()
                || name.len() > 128
                || name.chars().any(char::is_control)
                || id.is_empty()
                || id.len() > 256
            {
                return Err("Invalid sandbox identity".into());
            }
            Ok(Request::Action {
                verb: verb.clone(),
                name: name.clone(),
                id: id.clone(),
            })
        }
        _ => {
            Err("Usage: microsandbox-panel status | {start|stop|remove|shell|logs} NAME ID".into())
        }
    }
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct Row {
    id: String,
    name: String,
    status: String,
    running: bool,
    actionable: bool,
    image: String,
    resources: String,
    ports: Vec<String>,
    created_at: String,
    usage: Option<Usage>,
    metrics_note: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct Usage {
    cpu_summary: String,
    memory_summary: String,
    cpu_text: String,
    cpu_fraction: Option<f64>,
    memory_text: String,
    memory_fraction: Option<f64>,
}

// The sampler's CPU percentage uses 100% per core, not 100% per VM.
// Normalize against active allocated cores for the progress bar.
fn resource_usage(
    cpu_percent: f32,
    cpus: Option<u32>,
    used: u64,
    available: Option<u64>,
    limit: u64,
) -> Usage {
    let cpu = f64::from(cpu_percent);
    let (cpu_text, cpu_fraction, cpu_summary) = match cpus {
        Some(count) if count > 0 && cpu.is_finite() && cpu >= 0.0 => {
            let fraction = cpu / (100.0 * f64::from(count));
            (
                format!(
                    "CPU  {:.2} / {count} cores · {:.1}%",
                    cpu / 100.0,
                    fraction * 100.0
                ),
                Some(fraction.clamp(0.0, 1.0)),
                format!("CPU {:.1}%", fraction * 100.0),
            )
        }
        _ => ("CPU usage unavailable".into(), None, "CPU —".into()),
    };
    // The SDK encodes unavailable guest memory as zero. Don't turn that
    // into an apparently idle guest when the reporter is absent.
    let (memory_text, memory_fraction, memory_summary) =
        if limit > 0 && (used > 0 || available.is_some()) {
            let fraction = used as f64 / limit as f64;
            (
                format!(
                    "Memory  {:.0} / {:.0} MiB · {:.1}%",
                    used as f64 / 1048576.0,
                    limit as f64 / 1048576.0,
                    fraction * 100.0
                ),
                Some(fraction.clamp(0.0, 1.0)),
                format!("RAM {:.1}%", fraction * 100.0),
            )
        } else {
            (
                "Guest memory usage unavailable".into(),
                None,
                "RAM —".into(),
            )
        };
    Usage {
        cpu_summary,
        memory_summary,
        cpu_text,
        cpu_fraction,
        memory_text,
        memory_fraction,
    }
}

#[derive(Serialize, Default)]
#[serde(rename_all = "camelCase")]
struct Response {
    ok: bool,
    error: String,
    sandboxes: Vec<Row>,
    running_count: usize,
    truncated: bool,
}

// Only display fields cross the UI boundary: never serialize the full config,
// which may contain environment variables, credentials, or mounted host paths.
fn label(value: &str, limit: usize) -> String {
    value
        .chars()
        .filter(|c| {
            !c.is_control() && !matches!(*c, '\u{202a}'..='\u{202e}' | '\u{2066}'..='\u{2069}')
        })
        .take(limit)
        .collect()
}

fn row(handle: &SandboxHandle, report: Option<&SandboxMetricsReport>) -> Row {
    let status = format!("{:?}", handle.status_snapshot());
    let running = matches!(status.as_str(), "Running" | "Draining");
    let actionable = matches!(
        status.as_str(),
        "Running" | "Draining" | "Stopped" | "Crashed"
    );
    let mut image = String::new();
    let mut resources = String::new();
    let mut ports = Vec::new();
    if let Ok(config) = handle.config() {
        use microsandbox::sandbox::{PortProtocol, RootfsSource};
        image = label(
            &match &config.spec.image {
                RootfsSource::Oci(oci) => oci.reference.clone(),
                RootfsSource::Bind { .. } => "Host filesystem".into(),
                RootfsSource::DiskImage { .. } => "Disk image".into(),
            },
            200,
        );
        let active = handle.active_config().ok().flatten();
        let r = &active.as_ref().unwrap_or(&config).spec.resources;
        resources = format!("{} CPU · {} MiB", r.cpus, r.memory_mib);
        for p in config.spec.network.ports.iter().take(16) {
            ports.push(label(
                &format!(
                    "{}:{} → {}/{}",
                    p.host_bind,
                    p.host_port,
                    p.guest_port,
                    match p.protocol {
                        PortProtocol::Tcp => "tcp",
                        PortProtocol::Udp => "udp",
                    }
                ),
                100,
            ));
        }
    }
    let (usage, metrics_note) = if !running {
        (None, String::new())
    } else if let Some(report) = report {
        if report.state == SandboxMetricsState::Running {
            let m = &report.metrics;
            (
                Some(resource_usage(
                    m.cpu_percent,
                    report.cpus,
                    m.memory_bytes,
                    m.memory_available_bytes,
                    m.memory_limit_bytes,
                )),
                format!("Sampled {} UTC", m.timestamp.format("%H:%M:%S")),
            )
        } else {
            (
                None,
                "Usage sample is stale; waiting for the runtime sampler".into(),
            )
        }
    } else {
        (
            None,
            "Usage unavailable — sampling may be disabled or not ready".into(),
        )
    };
    Row {
        id: handle.id().to_string(),
        name: handle.name().to_string(),
        status,
        running,
        actionable,
        image,
        resources,
        ports,
        usage,
        metrics_note,
        created_at: handle
            .created_at()
            .map(|d| d.format("%Y-%m-%d %H:%M UTC").to_string())
            .unwrap_or_default(),
    }
}

async fn status(local: &LocalBackend) -> Result<Response> {
    // Registry-backed batch read: no guest command, connection, or VM mutation.
    // Failure of optional metrics must never hide the management controls.
    let reports: HashMap<_, _> = tokio::time::timeout(
        Duration::from_secs(2),
        all_sandbox_metrics_reports_local(local, false),
    )
    .await
    .ok()
    .and_then(std::result::Result::ok)
    .unwrap_or_default()
    .into_iter()
    .map(|r| ((r.sandbox_id, r.name.clone()), r))
    .collect();
    let mut rows = Vec::new();
    let mut cursor: Option<String> = None;
    let mut truncated = false;
    // The SDK defaults to 20 entries. Explicitly paginate, with a hard UI cap.
    loop {
        let page = Sandbox::list_with(|b| match &cursor {
            Some(c) => b.limit(100).cursor(c.clone()),
            None => b.limit(100),
        })
        .await?;
        rows.extend(page.sandboxes.iter().map(|h| {
            let report = h
                .local()
                .and_then(|s| reports.get(&(s.db_id, h.name().to_string())));
            row(h, report)
        }));
        cursor = page.next_cursor;
        if rows.len() >= MAX_ROWS {
            truncated = cursor.is_some() || rows.len() > MAX_ROWS;
            rows.truncate(MAX_ROWS);
            break;
        }
        if cursor.is_none() {
            break;
        }
    }
    rows.sort_by(|a, b| b.running.cmp(&a.running).then_with(|| a.name.cmp(&b.name)));
    let running_count = rows.iter().filter(|r| r.running).count();
    Ok(Response {
        ok: true,
        sandboxes: rows,
        running_count,
        truncated,
        ..Default::default()
    })
}

fn verify_identity(actual: &str, expected: &str) -> Result<()> {
    if actual != expected {
        return Err("Sandbox identity changed; refresh before trying again".into());
    }
    Ok(())
}

fn msb_path() -> Result<std::path::PathBuf> {
    let mut paths = Vec::new();
    if let Some(path) = std::env::var_os("MSB_PATH") {
        paths.push(path.into());
    }
    if let Some(home) = std::env::var_os("HOME") {
        let home = std::path::PathBuf::from(home);
        paths.push(home.join(".local/bin/msb"));
        paths.push(home.join(".microsandbox/bin/msb"));
    }
    if let Some(path) = std::env::var_os("PATH") {
        paths.extend(std::env::split_paths(&path).map(|p| p.join("msb")));
    }
    use std::os::unix::fs::PermissionsExt;
    paths
        .into_iter()
        .find(|p| {
            p.is_file()
                && p.metadata()
                    .is_ok_and(|m| m.permissions().mode() & 0o111 != 0)
        })
        .ok_or_else(|| "Cannot locate installed msb executable".into())
}

async fn execute(req: Request, local: &LocalBackend) -> Result<Response> {
    if let Request::Action { verb, name, id } = req {
        let h = Sandbox::get(&name).await?;
        verify_identity(h.id().as_ref(), &id)?;
        match verb.as_str() {
            "start" => {
                let sb = h.start_detached().await?;
                sb.detach().await;
            }
            "stop" => h.stop().await?,
            // Deliberately don't force-stop: remove only stopped sandboxes.
            "remove" => h.remove().await?,
            "shell" | "logs" => {
                // Interactive terminals are intentionally delegated to the existing CLI.
                let mut cmd = std::process::Command::new("omarchy-launch-tui");
                cmd.arg("--app-id=org.omarchy.microsandbox")
                    .arg(msb_path()?);
                if verb == "shell" {
                    cmd.arg("ssh");
                } else {
                    cmd.args(["logs", "-f"]);
                }
                let outcome = cmd
                    .arg("--")
                    .arg(&name)
                    .stdin(std::process::Stdio::null())
                    .stdout(std::process::Stdio::null())
                    .stderr(std::process::Stdio::null())
                    .status()?;
                if !outcome.success() {
                    return Err("Omarchy terminal launcher failed".into());
                }
            }
            _ => unreachable!(),
        }
    }
    status(local).await
}

#[tokio::main]
async fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if args == ["--help"] || args == ["-h"] {
        println!(
            "microsandbox-panel status\nmicrosandbox-panel {{start|stop|remove|shell|logs}} NAME ID\nLocal-only SDK backend. Remove only accepts stopped sandboxes."
        );
        return;
    }
    let outcome: Result<Response> = async {
        let req = request(&args)?;
        let timeout = if req == Request::Status { 20 } else { 180 };
        // Explicitly local: never select a cloud backend from ambient credentials.
        // No install/ensure calls; use the user's already installed runtime.
        let backend = Arc::new(LocalBackend::lazy()?);
        let dispatch: Arc<dyn microsandbox::Backend> = backend.clone();
        tokio::time::timeout(
            Duration::from_secs(timeout),
            with_backend(dispatch, execute(req, &backend)),
        )
        .await
        .map_err(|_| "Operation timed out; refresh to check its final state")?
    }
    .await;
    let response = match outcome {
        Ok(r) => r,
        Err(e) => Response {
            error: label(&e.to_string(), 500),
            ..Default::default()
        },
    };
    let failed = !response.ok;
    println!(
        "{}",
        serde_json::to_string(&response).expect("serializing display response")
    );
    if failed {
        std::process::exit(1);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn args(a: &[&str]) -> Vec<String> {
        a.iter().map(|s| s.to_string()).collect()
    }
    #[test]
    fn accepts_only_explicit_commands() {
        assert_eq!(request(&args(&["status"])).unwrap(), Request::Status);
        assert!(request(&args(&["rm", "box", "local:1"])).is_err());
        assert!(request(&args(&["start", "box"])).is_err());
        assert!(request(&args(&["status", "extra"])).is_err());
    }
    #[test]
    fn rejects_malformed_names() {
        for name in ["", "box\nother", "a\0b", &"a".repeat(129)] {
            assert!(request(&args(&["stop", name, "local:1"])).is_err());
        }
    }
    #[test]
    fn preserves_names_as_data() {
        assert!(request(&args(&["start", "it's $(not a shell)", "local:1"])).is_ok());
    }
    #[test]
    fn guards_against_recreated_sandboxes() {
        assert!(verify_identity("local:2", "local:1").is_err());
        assert!(verify_identity("local:1", "local:1").is_ok());
    }
    #[test]
    fn clips_and_sanitizes_display_text() {
        assert_eq!(label("hello\n\u{1b}\u{202e}world", 7), "hellowo");
        assert_eq!(label("ééé", 2), "éé");
    }
    #[test]
    fn cpu_is_normalized_against_allocated_cores() {
        let u = resource_usage(
            100.0,
            Some(2),
            512 * 1048576,
            Some(512 * 1048576),
            1024 * 1048576,
        );
        assert_eq!(u.cpu_fraction, Some(0.5));
        assert!(u.cpu_text.contains("1.00 / 2 cores · 50.0%"));
        assert_eq!(u.cpu_summary, "CPU 50.0%");
        assert_eq!(u.memory_summary, "RAM 50.0%");
        assert_eq!(u.memory_fraction, Some(0.5));
        assert!(u.memory_text.contains("512 / 1024 MiB · 50.0%"));
    }
    #[test]
    fn missing_metrics_are_not_displayed_as_zero() {
        let u = resource_usage(f32::NAN, Some(0), 0, None, 0);
        assert_eq!(u.cpu_fraction, None);
        assert_eq!(u.memory_fraction, None);
        let u = resource_usage(0.0, Some(2), 0, Some(1024), 1024);
        assert_eq!(u.cpu_fraction, Some(0.0));
        assert_eq!(u.memory_fraction, Some(0.0));
    }
    #[test]
    fn usage_bars_are_bounded_without_hiding_overallocation() {
        let u = resource_usage(210.0, Some(2), 110, Some(0), 100);
        assert_eq!(u.cpu_fraction, Some(1.0));
        assert!(u.cpu_text.contains("105.0%"));
        assert_eq!(u.cpu_summary, "CPU 105.0%");
        assert_eq!(u.memory_fraction, Some(1.0));
    }
    #[test]
    fn failure_has_no_stale_rows() {
        let value = serde_json::to_value(Response::default()).unwrap();
        assert_eq!(value["ok"], false);
        assert_eq!(value["sandboxes"], serde_json::json!([]));
    }
}
