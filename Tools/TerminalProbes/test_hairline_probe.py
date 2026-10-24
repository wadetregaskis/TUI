"""Tests for the parts of `hairline_probe.py` that need no terminal: the
escapes it sends, how it reads replies and keys, how it names its record,
and the verdicts it draws.

    cd Tools/TerminalProbes && python3 -m unittest test_hairline_probe
    python3 -m unittest discover -s Tools/TerminalProbes -p 'test_*.py'

Where a test needs something to read keys from, that is one end of a socket
pair, with the test writing at the other.
"""
import glob
import json
import os
import socket
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import hairline_probe as probe  # noqa: E402  (the path has to be set up first)

DATA = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data")


class EscapeTests(unittest.TestCase):

    def test_a_line_is_a_classic_placement_that_holds_the_cursor_and_names_itself(self):
        self.assertEqual(
            probe.place(probe.STRIP_ID, 7, 1264, 2),
            b"\x1b_Ga=p,i=16777200,p=7,x=0,y=0,w=1264,h=2,C=1,z=-1,q=0\x1b\\")
        # No `U=1` (that is a virtual placement) and no `c`/`r` (hosts
        # disagree on letterboxing against stretching when both are given).
        self.assertNotIn(b"U=", probe.place(probe.STRIP_ID, 7, 1264, 2))
        self.assertNotIn(b",c=", probe.place(probe.STRIP_ID, 7, 1264, 2))

    def test_no_layer_is_z_zero_and_the_lowest_is_under_painted_cells(self):
        # iTerm2 draws z=0 under text; the spec puts anything below
        # INT32_MIN/2 under cells with a non-default background.
        for z in (probe.Z_UNDER_TEXT, probe.Z_OVER_TEXT, probe.Z_UNDER_FILLS):
            self.assertNotEqual(z, 0)
        self.assertLess(probe.Z_UNDER_FILLS, -(2 ** 31) // 2)
        self.assertGreaterEqual(probe.Z_UNDER_FILLS, -(2 ** 31))

    def test_a_delete_keeps_the_data_unless_asked_to_free_it(self):
        self.assertEqual(probe.delete(probe.STRIP_ID, 3),
                         b"\x1b_Ga=d,d=i,i=16777200,p=3,q=2\x1b\\")
        self.assertEqual(probe.delete(probe.STRIP_ID, free=True, quiet=False),
                         b"\x1b_Ga=d,d=I,i=16777200,q=0\x1b\\")

    def test_the_strip_is_sent_in_chunks_that_the_last_one_closes(self):
        sent = probe.transmit(bytes(probe.LINE) * (2048 * 2), probe.STRIP_ID, 2048, 2)
        chunks = sent.split(b"\x1b\\")[:-1]
        self.assertEqual(len(chunks), 4)  # 12,288 bytes of RGB is 16,384 of base64
        self.assertIn(b"a=t,t=d,f=24,s=2048,v=2,i=16777200,q=0,m=1;", chunks[0])
        self.assertTrue(chunks[-1].startswith(b"\x1b_Gm=0;"))

    def test_the_probe_ids_stay_beside_the_handshake_ids(self):
        self.assertEqual(len(set(probe.PROBE_IDS)), len(probe.PROBE_IDS))
        for image_id in probe.PROBE_IDS:
            self.assertLess(image_id, probe.MAXIMUM_ID - 1)  # the handshake owns the top two
            self.assertGreater(image_id, probe.MAXIMUM_ID - 16)


class GeometryTests(unittest.TestCase):
    # iTerm2's shape: a cell that is not a whole number of pixels.
    ITERM = {"rows": 40, "columns": 120, "xpixel": 1710, "ypixel": 1360}

    def test_the_crop_multiplies_before_it_divides(self):
        self.assertEqual(probe.crop_width(self.ITERM, 120), 1710)
        self.assertEqual(probe.crop_width(self.ITERM, 40), 570)
        self.assertEqual(40 * (1710 // 120), 560)  # what dividing first would lose

    def test_the_crop_can_be_taken_from_the_measure_that_is_the_unit(self):
        windows = probe.xtwinops(b"\x1b[4;680;855t\x1b[6;17;7t\x1b[8;40;120t")  # points: half the ioctl's
        self.assertEqual(probe.crop_width(self.ITERM, 40, windows, "csi_14t"), 285)
        self.assertEqual(probe.crop_width(self.ITERM, 40, windows, "csi_16t"), 280)
        self.assertEqual(probe.crop_width(self.ITERM, 40, windows), 570)
        # A measure that was not answered falls back to TIOCGWINSZ's.
        self.assertEqual(probe.crop_width(self.ITERM, 40, {}, "csi_16t"), 570)

    def test_the_fine_lines_end_short_of_the_edge_one_per_distinct_width(self):
        windows = probe.xtwinops(b"\x1b[4;1360;1710t\x1b[6;34;14t\x1b[8;40;120t")
        variants = probe.fine_variants(self.ITERM, windows, 116)
        # 14 t's width equals ws_xpixel and 16 t's cell equals ws_xpixel // ws_col
        # here, so they add no line of their own.
        self.assertEqual([(letter, width) for letter, _, width in variants], [("A", 1653), ("B", 1624)])
        points = probe.xtwinops(b"\x1b[4;680;855t\x1b[6;17;7t")
        self.assertEqual([width for _, _, width in probe.fine_variants(self.ITERM, points, 116)],
                         [1653, 1624, 826, 812])
        self.assertEqual(probe.fine_variants({"rows": 24, "columns": 80, "xpixel": 0, "ypixel": 0}, {}, 76), [])

    def test_a_host_without_pixels_gets_the_default_cell(self):
        geometry = {"rows": 24, "columns": 80, "xpixel": 0, "ypixel": 0}
        self.assertEqual(probe.crop_width(geometry, 10), 80)
        self.assertEqual(probe.line_thickness(geometry), 1)

    def test_the_line_is_about_a_point_thick(self):
        self.assertEqual(probe.line_thickness({"rows": 17, "columns": 49, "xpixel": 784, "ypixel": 578}), 2)
        self.assertEqual(probe.line_thickness({"rows": 24, "columns": 80, "xpixel": 640, "ypixel": 384}), 1)

    def test_every_measure_of_a_cell_is_kept_by_its_source(self):
        windows = probe.xtwinops(b"\x1b[4;1360;1710t\x1b[6;34;14t\x1b[8;40;120t")
        self.assertEqual(windows, {"csi_14t_text_area_px": [1360, 1710], "csi_16t_cell_px": [34, 14],
                                   "csi_18t_text_area_cells": [40, 120]})
        self.assertEqual(probe.cell_widths(self.ITERM, windows),
                         {"ioctl": 14, "csi_14t": 14.25, "csi_16t": 14})
        self.assertEqual(probe.xtwinops(None)["csi_16t_cell_px"], None)
        self.assertEqual(probe.xtwinops(probe.OUT_OF_STEP)["csi_14t_text_area_px"], None)
        self.assertEqual(probe.replies(probe.OUT_OF_STEP), [])

    def test_a_coarse_advance_names_a_2x_unit_error(self):
        self.assertEqual(probe.unit_reading(10), "same unit")
        self.assertIn("half", probe.unit_reading(20))
        self.assertIn("twice", probe.unit_reading(5))
        self.assertIn("did not move", probe.unit_reading(0))
        self.assertEqual(probe.unit_reading(None), "no cursor report")

    def test_the_unit_is_tioctls_when_it_can_be_and_none_when_nothing_matches(self):
        def coarse(**advances):
            return {source: {"advance": advance, "reading": probe.unit_reading(advance)}
                    for source, advance in advances.items()}
        self.assertEqual(probe.unit_source(coarse(ioctl=10, csi_14t=10)), "ioctl")
        self.assertEqual(probe.unit_source(coarse(ioctl=20, csi_14t=10)), "csi_14t")
        self.assertIsNone(probe.unit_source(coarse(ioctl=20, csi_14t=20)))
        self.assertEqual(probe.unit_source(coarse(ioctl=None)), "unmeasured")
        self.assertEqual(probe.unit_source({}), "unmeasured")


class ReplyTests(unittest.TestCase):

    def test_a_reply_is_read_for_its_own_placement(self):
        raw = (b"\x1b_Gi=16777200,p=1;OK\x1b\\"
               b"\x1b_Gi=16777200,p=2;ENOENT:image not found\x1b\\")
        self.assertEqual(probe.status(raw, probe.STRIP_ID, 1), "OK")
        self.assertEqual(probe.status(raw, probe.STRIP_ID, 2), "ENOENT")
        self.assertEqual(probe.status(raw, probe.SCRATCH_ID), "silent")

    def test_silence_and_a_missing_fence_are_different_answers(self):
        self.assertEqual(probe.status(b"", probe.STRIP_ID), "silent")
        self.assertEqual(probe.status(None, probe.STRIP_ID), "no fence")

    def test_a_host_that_leaves_out_p_still_answers_for_the_placement(self):
        self.assertEqual(probe.status(b"\x1b_Gi=16777200;EINVAL:bad\x1b\\", probe.STRIP_ID, 4), "EINVAL")

    def test_a_reply_without_p_is_taken_only_when_it_is_the_only_one(self):
        # A late transmit OK beside this placement's own refusal: the one
        # that names the placement is its reply.
        raw = b"\x1b_Gi=16777200;OK\x1b\\\x1b_Gi=16777200,p=41;ENOENT:gone\x1b\\"
        self.assertEqual(probe.status(raw, probe.STRIP_ID, 41), "ENOENT")
        # Two replies, neither naming the placement: neither is taken for it.
        raw = b"\x1b_Gi=16777200;OK\x1b\\\x1b_Gi=16777200,p=7;OK\x1b\\"
        self.assertEqual(probe.status(raw, probe.STRIP_ID, 41), "silent")
        # A transmit's reply carries no p, and is preferred to a placement's.
        raw = b"\x1b_Gi=16777200,p=7;ENOENT:gone\x1b\\\x1b_Gi=16777200;OK\x1b\\"
        self.assertEqual(probe.status(raw, probe.STRIP_ID), "OK")

    def test_a_reading_skipped_out_of_step_is_neither_a_pass_nor_a_fail(self):
        self.assertEqual(probe.status(probe.OUT_OF_STEP, probe.STRIP_ID, 1), probe.OUT_OF_STEP)
        for skipped in ("no fence", probe.OUT_OF_STEP):
            questions = {"Q1": {"auto": {"place": {"status": skipped}},
                                "human": {"visible": {"answer": "yes"}, "on_boundary": {"answer": "yes"}}}}
            self.assertIsNone(probe.criteria(questions)["kill_inputs"]["q1_placed_and_drawn"])

    def test_a_named_refusal_is_kept_whole(self):
        # Warp's spelling for a virtual placement, measured 2026-09-02.
        refusal = b"InvalidKittyAction(InvalidControlData(UnicodePlaceholderUnsupported))"
        self.assertEqual(probe.status(b"\x1b_Gi=16777200;" + refusal + b"\x1b\\", probe.STRIP_ID),
                         refusal.decode())


class KeyTests(unittest.TestCase):

    def setUp(self):
        self.reader, self.writer = socket.socketpair()

    def tearDown(self):
        self.reader.close()
        self.writer.close()

    def test_terminal_replies_are_not_taken_for_keys(self):
        self.writer.sendall(b"\x1b_Gi=1;OK\x1b\\\x1b[3;1R\x1b[?2026;2$y" + b"n")
        self.assertEqual(probe.read_choice(self.reader.fileno(), ["y", "n", "s"], 1), "n")

    def test_q_and_ctrl_c_stop_the_run(self):
        for key in (b"q", b"\x03"):
            self.writer.sendall(key)
            with self.assertRaises(probe.Aborted):
                probe.read_choice(self.reader.fileno(), ["y", "n", "s"], 1)

    def test_a_q_typed_between_cards_stops_the_run_and_late_replies_do_not(self):
        self.writer.sendall(b"\x1b_Gi=16777200,p=71;ENOENT:image not found\x1b\\\x1b[9;11R")
        probe.drain(self.reader.fileno())  # replies alone: discarded
        self.writer.sendall(b"\x1b_Gi=16777200;OK\x1b\\q")
        with self.assertRaises(probe.Aborted):
            probe.drain(self.reader.fileno())

    @mock.patch.object(probe, "QUERY_TIMEOUT", 0.05)
    def test_a_missed_fence_is_followed_by_a_resync_that_discards_its_late_replies(self):
        run = probe.Probe(self.reader.fileno(), auto=True)
        # What a missed fence leaves queued, then the answer to the resync.
        self.writer.sendall(b"\x1b_Gi=16777200;OK\x1b\\\x1b[9;11R")
        self.writer.setblocking(False)
        run.resync("a fence that never came back", timeout=0.05)
        self.assertTrue(run.out_of_step)  # no DA1 answer yet: nothing is read
        self.assertEqual(run.ask(b"\x1b_Ga=p,i=1,q=0\x1b\\"), probe.OUT_OF_STEP)
        self.assertIsNone(run.cursor())
        # The host catches up: it answers every DA1 the probe has sent (the
        # first resync's and one per skipped reading), and the one the next
        # settle sends; then the next reading reads its own reply.
        sent = self.writer.recv(65536)
        self.assertIn(b"\x1b_Ga=p,i=1,q=0\x1b\\", sent)  # the command still went out,
        self.assertNotIn(b"\x1b[6n", sent)                # but nothing was fenced or read
        self.assertEqual(sent.count(probe.RESYNC), 3)
        self.writer.sendall(b"\x1b[?62;22c" * 4)
        self.assertTrue(run.settle())
        self.writer.sendall(b"\x1b_Gi=16777200,p=3;ENOENT:x\x1b\\\x1b[9;11R")
        self.assertEqual(run.exchange(b"", probe.STRIP_ID, 3)["status"], "ENOENT")
        self.assertEqual(run.missed_fences[0]["why"], "a fence that never came back")
        self.assertEqual(run.missed_fences[0]["in_step_after"], True)
        self.assertEqual(len(run.missed_fences), 1)

    def test_an_unanswered_question_turns_the_rest_of_the_run_automatic(self):
        run = probe.Probe(self.reader.fileno(), auto=False)
        entry = run.section("Q1", "a question")
        with mock.patch.object(probe, "ANSWER_TIMEOUT", 0.05):
            answer = run.human(entry, "visible", "Is there a line?")
        self.assertTrue(answer.startswith("no answer within"))
        self.assertTrue(run.auto)
        self.assertEqual(run.went_automatic, "Q1 visible")
        self.assertIsNone(run.human(entry, "on_boundary", "Is it on the boundary?"))
        self.assertNotIn("on_boundary", entry["human"])


class RestoreTests(unittest.TestCase):

    def setUp(self):
        self.terminal, self.probe_end = socket.socketpair()

    def tearDown(self):
        self.terminal.close()
        self.probe_end.close()

    def test_a_write_to_a_terminal_that_stopped_reading_gives_up_at_its_deadline(self):
        self.probe_end.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 4096)
        started = probe.time.monotonic()
        self.assertFalse(probe.write_by(self.probe_end.fileno(), b"x" * (4 << 20), started + 0.05))
        self.assertLess(probe.time.monotonic() - started, 2.0)
        self.terminal.setblocking(False)
        try:
            while self.terminal.recv(1 << 16):  # the terminal reads again
                pass
        except BlockingIOError:
            pass
        self.assertTrue(probe.write_by(self.probe_end.fileno(), b"y", probe.time.monotonic() + 1))
        # The descriptor is left blocking, as it was.
        self.assertFalse(probe.fcntl.fcntl(self.probe_end.fileno(), probe.fcntl.F_GETFL) & probe.os.O_NONBLOCK)

    @mock.patch.object(probe, "RESTORE_SECONDS", 0.1)
    def test_the_restore_closes_a_load_a_signal_cut_short_before_it_deletes_and_leaves(self):
        run = probe.Probe(self.probe_end.fileno(), auto=True)
        run.graphics_answered, run.on_alternate, run.loading = True, True, True
        self.terminal.sendall(b"\x1b[1;1R")  # the answer that ends the swallow of late replies
        run.restore()
        sent = self.terminal.recv(65536)
        self.assertTrue(sent.startswith(probe.ST + probe.CLOSE_LOAD))
        self.assertLess(sent.index(probe.CLOSE_LOAD), sent.index(b"a=d,d=I"))
        self.assertLess(sent.index(b"a=d,d=I"), sent.index(b"\x1b[?1049l"))
        self.assertFalse(run.on_alternate or run.loading)
        # With no transmit in flight there is nothing to close.
        self.terminal.sendall(b"\x1b[1;1R")
        run.restore()
        self.assertNotIn(probe.CLOSE_LOAD, self.terminal.recv(65536))


class NamingTests(unittest.TestCase):

    def test_hosts_are_named_as_the_committed_records_name_them(self):
        records = sorted(glob.glob(os.path.join(DATA, "*-placement.json"))
                         + glob.glob(os.path.join(DATA, "*-graphics.json")))
        self.assertGreater(len(records), 0)
        for path in records:
            with open(path) as handle:
                env = json.load(handle)["env"]
            # GNOME Terminal and other hosts without TERM_PROGRAM or LC_TERMINAL
            # in their environment are named manually when recorded rather than
            # by host_slug(env).
            if not any(key in env for key in ("TERM_PROGRAM", "LC_TERMINAL")):
                continue
            name = os.path.basename(path)
            self.assertEqual(probe.host_slug(env) + name[name.rfind("-"):], name)

    def test_a_host_without_term_program_is_named_by_lc_terminal_or_xtversion(self):
        self.assertEqual(probe.host_slug({}, "kitty(0.42.1)"), "kitty-0.42.1")
        self.assertEqual(probe.host_slug({}, "WezTerm 20240203-110809-5046fc22"),
                         "wezterm-20240203-110809-5046fc22")
        self.assertEqual(probe.host_slug({"LC_TERMINAL": "iTerm2", "LC_TERMINAL_VERSION": "3.7.3"}),
                         "iterm2-3.7.3")
        self.assertEqual(probe.host_slug({"TERM": "xterm-256color"}), "xterm-256color-unknown-version")

    def test_a_term_program_inherited_from_another_terminal_gives_way_to_xtversion(self):
        # kitty started from an iTerm2 shell keeps iTerm2's variables; its run
        # must not be written over iTerm2's record.
        inherited = {"TERM_PROGRAM": "iTerm.app", "TERM_PROGRAM_VERSION": "3.6.11",
                     "LC_TERMINAL": "iTerm2", "LC_TERMINAL_VERSION": "3.6.11", "TERM": "xterm-kitty"}
        self.assertEqual(probe.host_slug(inherited, "kitty(0.42.1)"), "kitty-0.42.1")
        slug, source = probe.host_identity(inherited, "kitty(0.42.1)")
        self.assertIn("XTVERSION", source)
        self.assertIn("iTerm.app", source)
        self.assertEqual(probe.host_slug({"LC_TERMINAL": "iTerm2", "LC_TERMINAL_VERSION": "3.6.11"},
                                         "kitty(0.42.1)"), "kitty-0.42.1")

    def test_xtversion_that_names_the_same_program_keeps_the_committed_spelling(self):
        self.assertEqual(probe.host_slug({"TERM_PROGRAM": "iTerm.app", "TERM_PROGRAM_VERSION": "3.6.11"},
                                         "iTerm2 3.6.11"), "iterm2-3.6.11")
        self.assertEqual(probe.host_slug({"TERM_PROGRAM": "ghostty", "TERM_PROGRAM_VERSION": "1.3.1"},
                                         "ghostty 1.3.1"), "ghostty-1.3.1")
        warp = {"TERM_PROGRAM": "WarpTerminal", "TERM_PROGRAM_VERSION": "v0.2026.08.26.17.59.stable_01"}
        self.assertEqual(probe.host_slug(warp, "Warp(v0.2026.08.26.17.59.stable_01)"),
                         "warpterminal-v0.2026.08.26.17.59.stable_01")
        self.assertEqual(probe.host_identity(warp, "Warp(v0.2026.08.26.17.59.stable_01)")[1], "TERM_PROGRAM")
        self.assertEqual(probe.host_slug({"TERM_PROGRAM": "tmux", "TERM_PROGRAM_VERSION": "3.7c"},
                                         "tmux 3.7c"), "tmux-3.7c")

    @staticmethod
    def run_record(mode="interactive", aborted=None, went_automatic_at=None, answered=True):
        human = {"visible": {"question": "?", "answer": "yes"}} if answered else "not asked (--auto)"
        return {"host": "ghostty-1.3.1", "mode": mode, "aborted": aborted,
                "went_automatic_at": went_automatic_at, "questions": {"Q1": {"human": human}}}

    def test_only_a_run_answered_to_the_end_replaces_a_record_a_person_answered(self):
        with tempfile.TemporaryDirectory() as directory:
            def path_for(**run):
                return os.path.basename(probe.default_out_path(self.run_record(**run), directory))
            main = os.path.join(directory, "ghostty-1.3.1-hairline.json")
            # Nothing there yet, or only an automatic record: every run takes the name.
            self.assertEqual(path_for(mode="auto", answered=False), "ghostty-1.3.1-hairline.json")
            probe.write_record(main, self.run_record(mode="auto", answered=False))
            self.assertEqual(path_for(mode="auto", answered=False), "ghostty-1.3.1-hairline.json")
            self.assertEqual(path_for(aborted="quit key", answered=False), "ghostty-1.3.1-hairline.json")
            # A person's record is there.
            probe.write_record(main, self.run_record())
            self.assertEqual(path_for(), "ghostty-1.3.1-hairline.json")
            self.assertEqual(path_for(mode="auto", answered=False), "ghostty-1.3.1-hairline-auto.json")

    def test_q_at_the_welcome_card_does_not_replace_a_record_a_person_answered(self):
        with tempfile.TemporaryDirectory() as directory:
            probe.write_record(os.path.join(directory, "ghostty-1.3.1-hairline.json"), self.run_record())
            # Interactive, stopped before anything was asked: no --auto flag at all.
            stopped = self.run_record(aborted="quit key", answered=False)
            self.assertEqual(os.path.basename(probe.default_out_path(stopped, directory)),
                             "ghostty-1.3.1-hairline-aborted.json")
            # Stopped part-way, with some answers: still not a whole record.
            partial = self.run_record(aborted="SIGTERM")
            self.assertEqual(os.path.basename(probe.default_out_path(partial, directory)),
                             "ghostty-1.3.1-hairline-aborted.json")

    def test_a_run_nobody_watched_does_not_replace_a_record_a_person_answered(self):
        with tempfile.TemporaryDirectory() as directory:
            probe.write_record(os.path.join(directory, "ghostty-1.3.1-hairline.json"), self.run_record())
            # The welcome card timed out and the rest ran automatic.
            unwatched = self.run_record(went_automatic_at="the welcome card", answered=False)
            self.assertEqual(os.path.basename(probe.default_out_path(unwatched, directory)),
                             "ghostty-1.3.1-hairline-auto.json")


class VerdictTests(unittest.TestCase):

    @staticmethod
    def answered(**answers):
        return {key: {"question": key, "answer": answer} for key, answer in answers.items()}

    def test_an_ok_alone_decides_nothing(self):
        questions = {"Q1": {"auto": {"place": {"status": "OK"}}, "human": "not asked (--auto)"}}
        self.assertIsNone(probe.criteria(questions)["kill_inputs"]["q1_placed_and_drawn"])
        self.assertTrue(probe.criteria(questions)["auto_signals"]["q1_acknowledged"])

    def test_a_line_drawn_on_the_boundary_passes_q1_and_a_refusal_fails_it(self):
        drawn = {"Q1": {"auto": {"place": {"status": "OK"}},
                        "human": self.answered(visible="yes", on_boundary="yes")}}
        self.assertIs(probe.criteria(drawn)["kill_inputs"]["q1_placed_and_drawn"], True)
        refused = {"Q1": {"auto": {"place": {"status": "EINVAL"}},
                          "human": self.answered(visible="no", on_boundary="can't tell")}}
        self.assertIs(probe.criteria(refused)["kill_inputs"]["q1_placed_and_drawn"], False)

    def test_answers_that_change_the_plan_are_named(self):
        questions = {
            "Q3": {"auto": {"coarse": {"ioctl": {"advance": 20}}, "unit_revealed_by": None}, "human": {}},
            "Q4": {"auto": {}, "human": self.answered(under_text_on_every_band="no",
                                                      over_text_crosses_glyphs="yes")},
            "Q5": {"auto": {}, "human": self.answered(kept_A="yes", kept_B="no", kept_C="yes", kept_D="yes")},
            "Q8": {"auto": {}, "human": self.answered(visible_after_ed2="no", visible_on_primary="yes")},
        }
        changes = " | ".join(probe.criteria(questions)["plan_changes"])
        self.assertIn("Q5: ESC[2K loses the line", changes)
        self.assertNotIn("ECH loses", changes)
        self.assertIn("Q3: no query reveals", changes)
        self.assertIn("Q4: z=-1", changes)
        self.assertIn("Q8: lines outlive", changes)

    def test_z_minus_1_hidden_under_fills_with_z_plus_1_showing_changes_the_plan_and_kills_nothing(self):
        # Konsole's shape: the fills cover z=-1, and z=+1 draws over the glyphs.
        questions = {"Q4": {"auto": {}, "human": self.answered(
            under_text_on_every_band="no", over_text_crosses_glyphs="yes", on_boundary="yes")}}
        found = probe.criteria(questions)
        self.assertIs(found["kill_inputs"]["q4_on_boundary_in_a_layer_that_shows"], True)
        self.assertIn("Q4: z=-1", " | ".join(found["plan_changes"]))

    def test_q4_fails_off_the_boundary_or_in_neither_layer(self):
        def q4(**answers):
            return probe.criteria({"Q4": {"auto": {}, "human": self.answered(**answers)}})[
                "kill_inputs"]["q4_on_boundary_in_a_layer_that_shows"]
        self.assertIs(q4(under_text_on_every_band="yes", over_text_crosses_glyphs="no",
                         on_boundary="no"), False)
        self.assertIs(q4(under_text_on_every_band="no", over_text_crosses_glyphs="no",
                         on_boundary="yes"), False)
        self.assertIsNone(q4(under_text_on_every_band="no", over_text_crosses_glyphs="can't tell",
                             on_boundary="yes"))

    def test_q6_needs_both_lines_shown_before_one_is_removed(self):
        def q6(**answers):
            return probe.criteria({"Q6": {"auto": {}, "human": self.answered(**answers)}})[
                "kill_inputs"]["q6_removed_by_id"]
        # One placement per image: line 2 replaced line 1, so "line 1 gone,
        # line 2 kept" was true before anything was deleted.
        self.assertIs(q6(both_shown="no", one_removed="yes"), False)
        self.assertIs(q6(both_shown="yes", one_removed="yes"), True)
        self.assertIs(q6(both_shown="yes", one_removed="no"), False)

    def test_q5_judges_the_rewrites_only_against_a_control_that_kept_its_line(self):
        nothing_drawn = {"Q5": {"auto": {}, "human": self.answered(
            kept_A="no", kept_B="no", kept_C="no", kept_D="no")}}
        found = probe.criteria(nothing_drawn)
        self.assertEqual(found["plan_changes"], [])
        self.assertIn("Q5: the control row A", " | ".join(found["unjudged"]))

    def test_c1_is_untested_where_c0_did_not_move_the_cursor_either(self):
        questions = {"Q2": {"auto": {"held": True}, "human": "no card"},
                     "Q3": {"auto": {"coarse": {"ioctl": {"advance": 0}, "csi_16t": {"advance": 0}},
                                     "unit_revealed_by": "unmeasured"}, "human": {}}}
        found = probe.criteria(questions)
        self.assertIsNone(found["auto_signals"]["q2_cursor_held"])
        self.assertIn("Q2:", " | ".join(found["unjudged"]))
        questions["Q3"]["auto"]["coarse"]["ioctl"]["advance"] = 10
        self.assertIs(probe.criteria(questions)["auto_signals"]["q2_cursor_held"], True)

    def test_the_store_model_tells_another_screens_store_from_freed(self):
        def readings(on_alternate, on_primary):
            return probe.q8_readings({"store_lookup_on_alternate": {"status": on_alternate},
                                      "store_lookup_on_primary": {"status": on_primary}})["store"]
        self.assertEqual(readings("OK", "OK"), "shared")
        self.assertEqual(readings("ENOENT", "OK"), "per_screen")
        self.assertEqual(readings("ENOENT", "ENOENT"), "freed_by_switch")
        self.assertEqual(readings("silent", "OK"), "unclear")

    def test_a_host_that_acknowledges_an_id_never_sent_reads_nothing_from_its_oks(self):
        everything_ok = {key: {"status": "OK"} for key in (
            "replace_1", "replace_1_after_none_left", "scratch_place_after_free", "ed2_replace",
            "switch_replace", "store_lookup_on_alternate", "store_lookup_on_primary")}
        lying = {"status": "OK"}
        q6, q8 = probe.q6_readings(everything_ok, lying), probe.q8_readings(everything_ok, lying)
        self.assertIsNone(q6["lowercase_delete_keeps_data"])
        self.assertIsNone(q6["uppercase_delete_frees"])
        self.assertEqual(q8["store"], "untrusted")
        self.assertIsNone(q8["ed2_keeps_data"])
        honest = {"status": "ENOENT"}
        self.assertIs(probe.q6_readings(everything_ok, honest)["lowercase_delete_keeps_data"], True)
        self.assertEqual(probe.q8_readings(everything_ok, honest)["store"], "shared")
        self.assertIs(probe.criteria({}, lying)["auto_signals"]["acknowledges_everything"], True)
        # The control id is the probe's own, so the restore deletes it too.
        self.assertIn(probe.NEVER_SENT_ID, probe.PROBE_IDS)

    def test_delete_readings(self):
        found = probe.q6_readings({"replace_1": {"status": "OK"},
                                   "replace_1_after_none_left": {"status": "ENOENT"},
                                   "scratch_place_after_free": {"status": "silent"}})
        self.assertEqual(found, {"lowercase_delete_keeps_data": True, "data_kept_with_no_placement": False,
                                 "uppercase_delete_frees": None})


if __name__ == "__main__":
    unittest.main()
