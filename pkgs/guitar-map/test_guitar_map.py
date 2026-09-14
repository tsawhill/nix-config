import ctypes as C
import os
import unittest

from guitar_map import (SDL, candidates, describe_observation, dinput_members, field_value,
                        hid_observe, mapping_string, nix_profile, parse_report_descriptor,
                        profile_entry, profile_slug)

# Two 8-bit axes (X, Rx), a 4-bit hat with 4 bits of padding, then six buttons
# and 2 bits of padding: the shape a simple guitar reports over raw HID.
GUITAR_DESCRIPTOR = bytes([
    0x05, 0x01, 0x09, 0x05, 0xa1, 0x01, 0x09, 0x01, 0xa1, 0x00,
    0x09, 0x30, 0x09, 0x33, 0x15, 0x00, 0x26, 0xff, 0x00, 0x75, 0x08, 0x95, 0x02, 0x81, 0x02,
    0xc0,
    0x09, 0x39, 0x15, 0x00, 0x25, 0x07, 0x75, 0x04, 0x95, 0x01, 0x81, 0x42,
    0x75, 0x04, 0x95, 0x01, 0x81, 0x03,
    0x05, 0x09, 0x19, 0x01, 0x29, 0x06, 0x15, 0x00, 0x25, 0x01,
    0x75, 0x01, 0x95, 0x06, 0x81, 0x02,
    0x75, 0x01, 0x95, 0x02, 0x81, 0x03,
    0xc0,
])


class ReportDescriptorTests(unittest.TestCase):
    def test_padding_advances_offsets_without_becoming_a_field(self):
        fields = parse_report_descriptor(GUITAR_DESCRIPTOR)
        self.assertEqual([(f.offset, f.size) for f in fields],
                         [(0, 8), (8, 8), (16, 4)] + [(24 + i, 1) for i in range(6)])

    def test_members_follow_hid_usage_and_declaration_order(self):
        members = dinput_members(parse_report_descriptor(GUITAR_DESCRIPTOR))
        self.assertEqual([m.name for m in members.values()],
                         ["lX", "lRx", "rgdwPOV[0]"] + [f"rgbButtons[{i}]" for i in range(6)])
        self.assertEqual([m.kind for m in members.values()],
                         ["axis", "axis", "pov"] + ["button"] * 6)

    def test_logical_range_is_captured_for_axis_scaling(self):
        axis = parse_report_descriptor(GUITAR_DESCRIPTOR)[0]
        self.assertEqual((axis.logical_min, axis.logical_max), (0, 255))

    def test_values_decode_from_a_packed_report(self):
        fields = parse_report_descriptor(GUITAR_DESCRIPTOR)
        report = bytes([0x80, 0xff, 0x03, 0x3f])
        self.assertEqual([field_value(report, f) for f in fields],
                         [128, 255, 3] + [1] * 6)

    def test_short_report_yields_no_value(self):
        fields = parse_report_descriptor(GUITAR_DESCRIPTOR)
        self.assertIsNone(field_value(bytes([0x00]), fields[-1]))

    def test_only_changed_members_are_offered(self):
        fields = parse_report_descriptor(GUITAR_DESCRIPTOR)
        members = dinput_members(fields)
        rest = {f: v for f, v in zip(fields, [128, 0, 8, 0, 0, 0, 0, 0, 0])}
        observed = hid_observe({}, rest, {**rest, fields[1]: 255, fields[5]: 1}, members)
        self.assertEqual([describe_observation(observed[n]) for n in sorted(observed)],
                         ["lRx 0->255..255 of 0..255", "rgbButtons[2]"])

    def test_axis_sweep_collapses_to_one_record_with_extremes(self):
        fields = parse_report_descriptor(GUITAR_DESCRIPTOR)
        members = dinput_members(fields)
        rest, observed = {fields[1]: 128}, {}
        for value in (140, 255, 200, 10):
            hid_observe(observed, rest, {fields[1]: value}, members)
        self.assertEqual(list(observed), ["lRx"])
        self.assertEqual(describe_observation(observed["lRx"]), "lRx 128->10..255 of 0..255")

    def test_released_button_is_not_offered(self):
        fields = parse_report_descriptor(GUITAR_DESCRIPTOR)
        members = dinput_members(fields)
        self.assertEqual(hid_observe({}, {fields[3]: 1}, {fields[3]: 0}, members), {})

    def test_profile_entries_carry_index_or_axis_range(self):
        fields = parse_report_descriptor(GUITAR_DESCRIPTOR)
        members = dinput_members(fields)
        observed = hid_observe({}, {fields[1]: 0, fields[2]: 8, fields[5]: 0},
                               {fields[1]: 255, fields[2]: 0, fields[5]: 1}, members)
        self.assertEqual(profile_entry(observed["rgbButtons[2]"]), {"kind": "button", "index": 2})
        self.assertEqual(profile_entry(observed["rgdwPOV[0]"]), {"kind": "pov", "index": 0})
        self.assertEqual(profile_entry(observed["lRx"]),
                         {"kind": "axis", "member": "lRx", "min": 0, "max": 255})


class ProfileTests(unittest.TestCase):
    def profile(self, **kwargs):
        return nix_profile("crkd-sg", mapping_string("0" * 32, "Guitar", {"a": "b0"}),
                           ("3651", "0010"), **kwargs)

    def test_measured_members_render_as_module_options(self):
        snippet = self.profile(dinput={
            "a": {"kind": "button", "index": 2},
            "dpup": {"kind": "pov", "index": 0},
            "rightx": {"kind": "axis", "member": "lRx", "min": 0, "max": 255},
        })
        self.assertIn('software.apps.gaming.guitarProfiles."crkd-sg" = {', snippet)
        self.assertIn('vendor = "3651";', snippet)
        self.assertIn("buttons = {\n          a = 2;\n        };", snippet)
        self.assertIn("povs = {\n          dpup = 0;\n        };", snippet)
        self.assertIn('rightx = {\n            member = "lRx";\n'
                      "            min = 0;\n            max = 255;\n          };", snippet)

    def test_unmeasured_profile_is_still_valid_nix(self):
        snippet = self.profile(hid_error="No read access to\n/dev/hidraw3.")
        self.assertIn("# DirectInput NOT measured: No read access to /dev/hidraw3.\n", snippet)
        self.assertIn("buttons = { };", snippet)
        self.assertIn("axes = { };", snippet)

    def test_device_without_usb_ids_skips_the_hidraw_rule(self):
        self.assertIn("usb = null;", nix_profile("g", "0" * 32 + ",G,a:b0,", None))

    def test_slug_is_a_file_and_attribute_name(self):
        self.assertEqual(profile_slug("CRKD SG (PC mode)"), "crkd-sg-pc-mode")
        self.assertEqual(profile_slug("???"), "guitar")


class CaptureTests(unittest.TestCase):
    def test_button_hat_and_noise(self):
        rest = ((0, 0), (0,), (200,))
        self.assertEqual(candidates(rest, ((0, 1), (3,), (800,)), "a", 12000),
                         ["b1", "h0.1", "h0.2"])

    def test_axis_direction_and_rest(self):
        for rest, active, target, expected in [
            (-32768, 32767, "rightx", "a0"),
            (32767, -32768, "rightx", "a0~"),
            (0, 30000, "righty", "+a0"),
            (0, -30000, "righty", "-a0"),
            (0, -30000, "a", "-a0"),
            (0, 30000, "leftx", "a0"),
        ]:
            with self.subTest(rest=rest, target=target):
                self.assertEqual(candidates(((), (), (rest,)), ((), (), (active,)),
                                            target, 12000), [expected])

    def test_held_button_is_not_new_input(self):
        self.assertEqual(candidates(((1,), (), ()), ((1,), (), ()), "a", 12000), [])

    def test_output_escapes_nix_and_mapping_delimiters(self):
        mapping = mapping_string("0" * 32, 'Guitar,\n${oops}"', {"a": "b0"})
        self.assertNotIn("\n", mapping)
        snippet = nix_profile("guitar", mapping, ("1209", "2882"))
        self.assertIn(r'\${oops}\"', snippet)
        self.assertIn("guitarProfiles", snippet)


@unittest.skipUnless(os.environ.get("GUITAR_MAP_SDL_LIBRARY"), "set SDL library for virtual-controller test")
class VirtualControllerTests(unittest.TestCase):
    def test_identical_guitars_and_reconnect(self):
        sdl = SDL()
        lib = sdl.lib
        lib.SDL_JoystickAttachVirtual.argtypes = [C.c_int, C.c_int, C.c_int, C.c_int]
        lib.SDL_JoystickAttachVirtual.restype = C.c_int
        lib.SDL_JoystickDetachVirtual.argtypes = [C.c_int]
        lib.SDL_JoystickSetVirtualButton.argtypes = [C.c_void_p, C.c_int, C.c_int]
        joys, controllers, instances = [], [], []
        try:
            for _ in range(2):
                index = lib.SDL_JoystickAttachVirtual(1, 4, 16, 1)
                self.assertGreaterEqual(index, 0, sdl.error())
                joy = sdl.JoystickOpen(index)
                joys.append(joy)
                instances.append(sdl.JoystickInstanceID(joy))
            guid = bytes(sdl.JoystickGetGUID(joys[0]).data).hex()
            self.assertEqual(guid, bytes(sdl.JoystickGetGUID(joys[1]).data).hex())
            self.assertNotEqual(*instances)
            mapping = mapping_string(guid, "Identical guitar", {"a": "b0"})
            self.assertGreaterEqual(sdl.GameControllerAddMapping(mapping.encode()), 0)
            for instance in instances:
                controller = sdl.GameControllerOpen(sdl.device_index(instance))
                self.assertTrue(controller, sdl.error())
                controllers.append(controller)
            for active in (0, 1):
                for i, joy in enumerate(joys):
                    lib.SDL_JoystickSetVirtualButton(joy, 0, int(i == active))
                sdl.snapshot(joys[0])
                self.assertEqual([sdl.GameControllerGetButton(c, 0) for c in controllers],
                                 [int(i == active) for i in range(2)])
            previous_index = sdl.device_index(instances[1])
            lib.SDL_JoystickDetachVirtual(sdl.device_index(instances[0]))
            self.assertLess(sdl.device_index(instances[1]), previous_index)
            with self.assertRaisesRegex(RuntimeError, "disconnected"):
                sdl.device_index(instances[0])
            # Reattaching the same model gets a new instance but the same mapping.
            index = lib.SDL_JoystickAttachVirtual(1, 4, 16, 1)
            joy = sdl.JoystickOpen(index)
            joys.append(joy)
            instance = sdl.JoystickInstanceID(joy)
            self.assertNotIn(instance, instances)
            instances.append(instance)
            self.assertEqual(guid, bytes(sdl.JoystickGetGUID(joy).data).hex())
            controller = sdl.GameControllerOpen(index)
            self.assertTrue(controller, sdl.error())
            controllers.append(controller)
            lib.SDL_JoystickSetVirtualButton(joy, 0, 1)
            sdl.snapshot(joy)
            self.assertEqual(sdl.GameControllerGetButton(controller, 0), 1)
        finally:
            for controller in controllers:
                sdl.GameControllerClose(controller)
            for joy in joys:
                sdl.JoystickClose(joy)
            for instance in reversed(instances):
                try:
                    index = sdl.device_index(instance)
                except RuntimeError:
                    continue
                lib.SDL_JoystickDetachVirtual(index)
            sdl.Quit()

    def test_real_sdl_mapping_and_remapping(self):
        sdl = SDL()
        lib = sdl.lib
        lib.SDL_JoystickAttachVirtual.argtypes = [C.c_int, C.c_int, C.c_int, C.c_int]
        lib.SDL_JoystickAttachVirtual.restype = C.c_int
        lib.SDL_JoystickDetachVirtual.argtypes = [C.c_int]
        for name in ("Button", "Axis", "Hat"):
            fn = getattr(lib, "SDL_JoystickSetVirtual" + name)
            fn.argtypes = [C.c_void_p, C.c_int, C.c_int]
            fn.restype = C.c_int
        index = lib.SDL_JoystickAttachVirtual(1, 4, 16, 1)
        self.assertGreaterEqual(index, 0, sdl.error())
        joy = sdl.JoystickOpen(index)
        controller = None
        try:
            guid = bytes(sdl.JoystickGetGUID(joy).data).hex()
            bindings = {"a": "b0", "start": "b11", "rightshoulder": "b8",
                        "dpup": "h0.1", "rightx": "a0~", "righty": "+a1",
                        "lefttrigger": "a2", "leftx": "a3"}
            self.assertGreaterEqual(sdl.GameControllerAddMapping(
                mapping_string(guid, "Test guitar", bindings).encode()), 0)
            controller = sdl.GameControllerOpen(index)
            self.assertTrue(controller, sdl.error())
            lib.SDL_JoystickSetVirtualButton(joy, 8, 1)
            lib.SDL_JoystickSetVirtualButton(joy, 11, 1)
            lib.SDL_JoystickSetVirtualHat(joy, 0, 1)
            lib.SDL_JoystickSetVirtualAxis(joy, 0, -32768)
            lib.SDL_JoystickSetVirtualAxis(joy, 1, 32767)
            lib.SDL_JoystickSetVirtualAxis(joy, 2, 32767)
            sdl.snapshot(joy)
            self.assertEqual(sdl.GameControllerGetButton(controller, 10), 1)  # RB
            self.assertEqual(sdl.GameControllerGetButton(controller, 6), 1)  # Start
            self.assertEqual(sdl.GameControllerGetButton(controller, 11), 1)  # D-pad up
            self.assertEqual(sdl.GameControllerGetAxis(controller, 2), 32767)
            self.assertEqual(sdl.GameControllerGetAxis(controller, 3), 32767)
            self.assertEqual(sdl.GameControllerGetAxis(controller, 4), 32767)
            sdl.GameControllerClose(controller)
            controller = None
            bindings["rightshoulder"] = "b9"
            sdl.GameControllerAddMapping(mapping_string(guid, "Test guitar", bindings).encode())
            controller = sdl.GameControllerOpen(index)
            sdl.snapshot(joy)
            self.assertEqual(sdl.GameControllerGetButton(controller, 10), 0)
        finally:
            if controller:
                sdl.GameControllerClose(controller)
            sdl.JoystickClose(joy)
            lib.SDL_JoystickDetachVirtual(index)
            sdl.Quit()


if __name__ == "__main__":
    unittest.main()
