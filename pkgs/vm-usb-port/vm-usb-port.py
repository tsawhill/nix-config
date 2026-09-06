"""Select a physical USB location and attach it to a running system VM."""

from pathlib import Path
import subprocess
import tempfile
import xml.etree.ElementTree as ET


def virsh(*args):
    result = subprocess.run(
        ["virsh", "--connect", "qemu:///system", *args],
        capture_output=True, text=True,
    )
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip())
    return result.stdout


def dialog(*args):
    result = subprocess.run(
        ["zenity", "--title=VM USB Port", "--no-markup", *args],
        capture_output=True, text=True,
    )
    if result.returncode == 1:
        return None  # User cancelled.
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or "Could not open the device picker.")
    return result.stdout.strip()


def usb_devices(root=Path("/sys/bus/usb/devices")):
    devices = {}
    for path in sorted(root.iterdir()):
        # Root hubs and USB interfaces are not individual attachable devices.
        if "-" not in path.name or ":" in path.name:
            continue
        try:
            def read(name):
                return (path / name).read_text().strip()
            if read("bDeviceClass") == "09":
                continue
            bus = str(int(read("busnum")))
            port = read("devpath")
            vendor, product = read("idVendor"), read("idProduct")
            label = read("product") if (path / "product").exists() else "USB device"
            devices[path.name] = (bus, port, vendor, product, label)
        except (OSError, ValueError):
            continue  # Device disappeared during enumeration.
    return devices


def port_xml(bus, port):
    device = ET.Element("hostdev", mode="subsystem", type="usb", managed="yes")
    source = ET.SubElement(device, "source", startupPolicy="optional")
    ET.SubElement(source, "address", bus=bus, port=port)
    return ET.tostring(device, encoding="unicode")


def main():
    domains = virsh("list", "--state-running", "--name").splitlines()
    domains = [name for name in domains if name]
    if not domains:
        dialog("--info", "--text=Start a VM in Virtual Machine Manager first.")
        return
    domain = dialog(
        "--list", "--column=Running VM", "--height=300", "--width=500",
        "--text=Choose the VM that should receive the USB port.", "--", *domains,
    )
    if not domain:
        return
    devices = usb_devices()
    if not devices:
        dialog("--info", "--text=No connected USB devices were found.")
        return
    rows = []
    for key, (_, _, vendor, product, label) in devices.items():
        rows.extend([key, label, f"{vendor}:{product}"])
    selected = dialog(
        "--list", "--column=Port", "--column=Connected device", "--column=USB ID",
        "--print-column=1", "--height=500", "--width=750", "--ok-label=Attach port",
        "--text=Choose a device to assign its physical USB port to Windows or another VM.\n"
        "Linux loses access to that device while attached. You can swap devices in this port.\n"
        "This applies only until the VM shuts down; no saved settings are changed.",
        "--", *rows,
    )
    if not selected:
        return
    expected = devices[selected]
    if usb_devices().get(selected) != expected:
        raise RuntimeError("The selected device changed or disconnected. Open the picker again.")
    bus, port, _, _, _ = expected
    with tempfile.NamedTemporaryFile(mode="w", suffix=".xml") as xml:
        xml.write(port_xml(bus, port))
        xml.flush()
        # Deliberately live-only: never use --config or --persistent here.
        virsh("attach-device", domain, xml.name, "--live")
    dialog(
        "--info", f"--text=Port {selected} is attached to {domain} for this session.\n"
        "Swap devices in the same socket and keep its upstream hub connected.\n"
        "USB 3 devices may use a different port path and need selecting again.\n"
        "To release it early, remove the USB device in Virtual Machine Manager.",
    )


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError) as error:
        subprocess.run([
            "zenity", "--error", "--no-markup", "--title=VM USB Port",
            "--text=" + str(error),
        ])
        raise SystemExit(1)
