//! Feature reports on hidraw nodes, straight on the ioctls.
//! Adapted from mchose-linux (MIT), https://github.com/alexfrih/mchose-linux

use std::fs::{self, File};
use std::io;
use std::os::unix::fs::MetadataExt;
use std::os::unix::io::AsRawFd;
use std::path::{Path, PathBuf};
use std::thread::sleep;
use std::time::{Duration, Instant};

// _IOC(_IOC_READ | _IOC_WRITE, 'H', nr, len)
const fn hidioc(nr: u32, len: usize) -> u64 {
    ((3u32 << 30) | ((len as u32) << 16) | ((b'H' as u32) << 8) | nr) as u64
}

pub struct HidRaw {
    file: File,
}

impl HidRaw {
    /// Open and take the same exclusive flock the wayle battery widget uses,
    /// so the two never interleave exchanges.
    pub fn open_locked(path: &Path, wait: Duration) -> io::Result<Self> {
        let file = File::options().read(true).write(true).open(path)?;
        let deadline = Instant::now() + wait;
        while unsafe { libc::flock(file.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB) } != 0 {
            let err = io::Error::last_os_error();
            if err.raw_os_error() != Some(libc::EWOULDBLOCK) || Instant::now() >= deadline {
                return Err(err);
            }
            sleep(Duration::from_millis(50));
        }
        Ok(Self { file })
    }

    /// SET_REPORT(Feature); `buf[0]` is the report ID.
    pub fn set_feature(&self, buf: &[u8]) -> io::Result<()> {
        let rc = unsafe { libc::ioctl(self.file.as_raw_fd(), hidioc(0x06, buf.len()) as _, buf.as_ptr()) };
        if rc < 0 {
            return Err(io::Error::last_os_error());
        }
        Ok(())
    }

    /// GET_REPORT(Feature); `buf[0]` carries the report ID in, the report out.
    pub fn get_feature(&self, buf: &mut [u8]) -> io::Result<usize> {
        let rc = unsafe { libc::ioctl(self.file.as_raw_fd(), hidioc(0x07, buf.len()) as _, buf.as_mut_ptr()) };
        if rc < 0 {
            return Err(io::Error::last_os_error());
        }
        Ok(rc as usize)
    }
}

#[derive(Clone)]
pub struct Node {
    pub dev: PathBuf,
    /// Inode and ctime of the /dev node: a replug recreates it, even under the same name.
    pub stamp: (u64, i64, i64),
    pub vid: u16,
    pub pid: u16,
    pub descriptor: Vec<u8>,
}

/// Every hidraw node with its USB IDs and report descriptor.
pub fn nodes() -> Vec<Node> {
    let Ok(entries) = fs::read_dir("/sys/class/hidraw") else {
        return Vec::new();
    };
    let mut entries: Vec<_> = entries.filter_map(Result::ok).collect();
    entries.sort_by_key(|e| e.file_name());
    entries
        .into_iter()
        .filter_map(|entry| {
            let sys = entry.path();
            let uevent = fs::read_to_string(sys.join("device/uevent")).ok()?;
            // HID_ID=bus:vendor:product, hex, zero-padded to 8
            let id = uevent.lines().find_map(|l| l.strip_prefix("HID_ID="))?;
            let mut parts = id.split(':').skip(1).map(|v| u32::from_str_radix(v, 16).unwrap_or(0) as u16);
            let dev = PathBuf::from("/dev").join(entry.file_name());
            let stamp = fs::metadata(&dev).map(|m| (m.ino(), m.ctime(), m.ctime_nsec())).unwrap_or_default();
            Some(Node {
                dev,
                stamp,
                vid: parts.next()?,
                pid: parts.next()?,
                descriptor: fs::read(sys.join("device/report_descriptor")).unwrap_or_default(),
            })
        })
        .collect()
}
