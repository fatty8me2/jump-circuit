#!/usr/bin/env python3
"""Jump Circuit - world sound effects: per-map footsteps and landings, movement
sounds (wall run, wall kick, mantle, air rush, boost, ice) and the machines.

Same conventions as tools/gen_audio.py (and it borrows its helpers): everything
is synthesised from maths and seeded noise - no samples - so no third-party
licences apply.  44.1 kHz mono 16-bit, peak normalised to -3 dBFS, DC removed.
One-shots get a short fade in / out; loops are rendered CIRCULARLY (noise is
filtered in the FFT domain over the whole loop, time-varying filters run over
three periods and keep the middle one, tones have a whole number of cycles,
events that run past the end wrap round to the start) and carry a smpl chunk,
so they repeat without a seam.

Usage (from anywhere):
    python tools/gen_world_sfx.py            # generate everything, then verify
    python tools/gen_world_sfx.py --verify   # only verify the files on disk
    python tools/gen_world_sfx.py --themes=toybox,fungal   # only those surfaces' footsteps and landings

Deterministic: every clip has its own RNG seeded from gen_audio.SEED plus the
CRC of "world_" + its name, so re-running gives bit-identical files.
Requires numpy.  Afterwards run Godot once with --import.
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_audio as ga  # noqa: E402  (osc, sweep, ad_env, fft_band, svf_bandpass, grain, place, write_wav ...)

SR = ga.SR
TAU = ga.TAU
PEAK_DB = ga.SFX_PEAK_DB
OUT = ga.OUT
SIZE_BUDGET = 52.0e6

THEMES = ("gardens", "foundry", "balance", "clockwork", "reef", "orbital", "ascent", "xeno", "volcano", "glacier", "desert",
          "manor", "armada", "candy", "carrier", "sakura", "jungle", "frontier", "neon", "doom", "abyss", "tempest", "void",
          "toybox", "fungal", "carnival", "olympus", "dino", "arcane", "arcade", "siege")

# ---------------------------------------------------------------------------
# clip table: name -> (seconds, loop).  The verifier checks the files against it.
# ---------------------------------------------------------------------------
CLIPS = {}


def _reg(name, dur, loop=False):
    CLIPS[name] = (dur, loop)


STEP_LEN = 0.16
LAND_LEN = 0.4
for _th in THEMES:
    for _i in range(1, 5):
        _reg("step_%s_%d" % (_th, _i), STEP_LEN)
    for _i in range(1, 4):
        _reg("land_%s_%d" % (_th, _i), LAND_LEN)
for _i in range(1, 5):
    _reg("wallstep_%d" % _i, 0.13)
for _i in range(1, 4):
    _reg("wallkick_%d" % _i, 0.4)
    _reg("mantle_%d" % _i, 0.45)
    _reg("prop_bonk_%d" % _i, 0.3)
    _reg("sweep_whoosh_%d" % _i, 0.5)
    _reg("thruster_cough_%d" % _i, 0.16)
    _reg("billboard_glitch_%d" % _i, 0.11)
for _i in range(1, 3):
    _reg("pendulum_whoosh_%d" % _i, 0.7)
    _reg("jelly_bounce_%d" % _i, 0.55)
    _reg("data_zip_%d" % _i, 0.25)
for _i in range(1, 5):
    _reg("data_chirp_%d" % _i, 0.16)
for _i in range(1, 4):
    _reg("spore_boing_%d" % _i, 0.6)
    _reg("bomb_impact_%d" % _i, 1.0)
for _i in range(1, 3):
    _reg("snapjaw_snap_%d" % _i, 0.55)
    _reg("basalt_sink_%d" % _i, 1.4)
    _reg("crust_crack_%d" % _i, 0.5)
    _reg("icicle_shatter_%d" % _i, 0.9)
    _reg("ice_crack_%d" % _i, 0.6)
    _reg("spike_trap_%d" % _i, 0.5)
    _reg("stone_grind_%d" % _i, 1.3)
for _i in range(1, 4):
    _reg("snow_thump_%d" % _i, 0.4)
for _n, _d in (("wallrun_latch", 0.35), ("land_heavy", 0.8), ("boost", 0.6),
               ("laser_on", 0.4), ("laser_off", 0.35),
               ("blink_appear", 0.4), ("blink_vanish", 0.45), ("blink_tick", 0.06),
               ("crusher_shudder", 0.45), ("crusher_slam", 1.2), ("crusher_rise", 0.9),
               ("piston_fire", 0.35), ("piston_clank", 0.45), ("piston_retract", 0.7),
               ("warp_whoosh", 0.9), ("platform_reform", 0.4),
               ("ladle_tip", 0.7), ("ladle_splash", 0.7), ("ladle_hiss", 1.0),
               ("vent_rumble", 0.8), ("vent_burst", 0.8),
               ("thruster_ignite", 0.6), ("thruster_cutoff", 0.6),
               ("flare_alarm", 0.14), ("flare_launch", 1.0),
               ("gravity_on", 0.6), ("gravity_off", 0.6),
               ("escape_tick", 0.35), ("escape_tock", 0.35),
               ("trolley_clunk", 0.6), ("counterweight_thud", 0.7),
               ("billboard_on", 0.45), ("billboard_off", 0.4),
               ("snapjaw_open", 0.7), ("geyser_erupt", 1.6), ("leviathan_call", 3.6),
               ("bomb_launch", 1.0), ("bomb_whistle", 2.0), ("crust_break", 1.0), ("eruption_boom", 2.8),
               ("icicle_crack", 0.5), ("icicle_fall", 0.8), ("gust_whoosh", 1.4), ("ice_break", 1.0),
               ("avalanche_rumble", 2.5),
               ("spike_retract", 0.6), ("quicksand_sink", 1.2), ("mirage_shimmer", 1.0), ("boulder_impact", 1.4)):
    _reg(_n, _d)
for _n, _d in (("air_rush", 2.5), ("wallrun_scrape", 1.0), ("ice_slide", 1.2),
               ("laser_hum", 1.0), ("conveyor_hum", 1.0), ("wind_loop", 2.0), ("motor_hum", 1.0),
               ("warp_hum", 1.5), ("ladle_pour", 1.5), ("vent_loop", 1.5), ("surge_loop", 2.0),
               ("thruster_burn", 1.2), ("flare_roar", 1.5), ("gravity_hum", 2.0),
               ("scanner_servo", 1.0), ("trolley_run", 1.2), ("pulley_rattle", 1.0),
               ("trimmer_buzz", 1.0), ("billboard_buzz", 1.0),
               ("drift_hum", 2.0), ("lava_rise", 2.5), ("fumarole_loop", 2.0), ("lavafall_loop", 2.0),
               ("avalanche_roar", 2.5), ("sandfall_loop", 2.0), ("dustdevil_loop", 2.0), ("boulder_roll", 2.0)):
    _reg(_n, _d, True)
# the second set of new worlds: Phantom Manor, Storm Armada, Sugar Rush, Super Carrier
for _n, _d in (("manor_phantom_waver", 0.6), ("manor_phantom_form", 0.8), ("manor_phantom_fade", 0.8),
               ("manor_gaze_open", 0.7), ("manor_chain_creak", 0.8), ("manor_board_creak", 0.6),
               ("manor_board_snap", 0.6), ("manor_coffin_slam", 0.9), ("manor_bell_toll", 2.0),
               ("manor_mirror_chime", 1.0),
               ("armada_cannon_fuse", 0.8), ("armada_cannon_fire", 1.2), ("armada_cannon_impact", 0.9),
               ("armada_swing_creak", 0.7), ("armada_rod_charge", 0.9), ("armada_lightning_strike", 1.2),
               ("armada_prop_spinup", 1.0), ("armada_mast_creak", 0.9), ("armada_mast_crash", 1.2),
               ("armada_ship_bell", 1.4), ("armada_salute", 1.5),
               ("candy_jelly_boing", 0.5), ("candy_jack_wind", 0.8), ("candy_jack_pop", 0.7),
               ("candy_soldier_turn", 0.4), ("candy_train_whistle", 1.2), ("candy_gumball_drop", 0.6),
               ("candy_gumball_splash", 0.8), ("candy_confetti", 0.9), ("candy_fireworks", 1.5),
               ("carrier_cat_hiss", 0.8), ("carrier_cat_launch", 1.2), ("carrier_cat_retract", 0.9),
               ("carrier_jet_spool", 1.2), ("carrier_wire_twang", 0.7), ("carrier_elevator_start", 0.6),
               ("carrier_elevator_stop", 0.6), ("carrier_door_klaxon", 1.0), ("carrier_door_grind", 1.2),
               ("carrier_launch_spool", 1.2), ("carrier_launch_shot", 1.2), ("carrier_launch_flyby", 1.5),
               ("carrier_jbd_raise", 1.0), ("carrier_jbd_lower", 1.0), ("carrier_lift_move", 1.0),
               ("carrier_flyover", 1.8)):
    _reg(_n, _d)
for _n, _d in (("manor_gaze_hum", 1.5), ("manor_possessed_creak", 1.5), ("manor_waltz_box", 3.6),
               ("armada_hull_creak", 1.5), ("armada_prop_loop", 1.0), ("armada_winch_loop", 1.0),
               ("candy_soldier_march", 1.6), ("candy_train_chug", 1.6), ("candy_gumball_roll", 1.2),
               ("carrier_jet_roar", 1.5), ("carrier_elevator_hum", 1.0)):
    _reg(_n, _d, True)
# the third set of new worlds: Sakura Peaks, Jungle Temple, Wild West Heist, Neon City
for _n, _d in (("sakura_bamboo_creak", 0.7), ("sakura_bamboo_snap", 0.9), ("sakura_bell_bong", 2.2),
               ("sakura_log_whoosh", 0.8), ("sakura_log_thump", 0.6), ("sakura_petal_sink", 0.7),
               ("sakura_shuriken_ring", 0.8), ("sakura_shoji_rattle", 0.8), ("sakura_shoji_slam", 0.6),
               ("sakura_gust_rise", 1.5), ("sakura_gust", 1.4), ("sakura_mallet_creak", 0.9), ("sakura_ram_creak", 0.7),
               ("sakura_chime", 1.4), ("sakura_fireworks", 2.0), ("sakura_finish_bell", 2.6),
               ("jungle_vine_creak", 0.7), ("jungle_raft_bump", 0.6), ("jungle_dart_click", 0.12),
               ("jungle_dart_volley", 0.7), ("jungle_plate_click", 0.4), ("jungle_gate_open", 1.6),
               ("jungle_gate_tick", 0.25), ("jungle_gate_close", 1.2), ("jungle_trap_tick", 0.12),
               ("jungle_boulder_rumble", 2.0), ("jungle_boulder_crash", 1.4), ("jungle_boulder_splash", 1.5),
               ("jungle_altar", 2.4),
               ("neon_car_horn", 0.8), ("neon_drone_chirp", 0.35), ("neon_drone_zap", 0.6), ("neon_holo_glitch", 0.9),
               ("neon_holo_off", 0.4), ("neon_holo_on", 0.4), ("neon_checkpoint", 1.0), ("neon_finish", 2.4),
               ("frontier_fuse_light", 0.5), ("frontier_dynamite_boom", 1.8), ("frontier_signal_bell", 1.2),
               ("frontier_signal_clank", 0.6), ("frontier_signal_thwack", 0.45),("frontier_timber_crack", 0.9), ("frontier_collapse_rebuild", 1.5),
               ("frontier_door_creak", 0.6), ("frontier_door_clack", 0.4), ("frontier_door_rattle", 0.5),
               ("frontier_door_slap", 0.5), ("frontier_steam_sputter", 0.7), ("frontier_steam_burst", 0.9),
               ("frontier_cart_clunk", 0.6), ("frontier_vault_open", 1.4), ("frontier_vault_slam", 1.0),
               ("frontier_coins", 0.8), ("frontier_whistle", 2.0), ("frontier_fireworks", 1.8)):
    _reg(_n, _d)
for _n, _d in (("sakura_shuriken_whir", 1.0), ("sakura_wind", 2.0), ("sakura_waterfall", 2.0), ("sakura_bridge_creak", 2.0),
               ("jungle_boulder_roll", 2.0), ("jungle_waterfall", 2.0),
               ("neon_car_hum", 1.0), ("neon_drone_hum", 1.0), ("neon_holo_hum", 1.0), ("neon_gondola_motor", 1.0),
               ("neon_steam_hiss", 1.5), ("neon_sign_buzz", 1.0),
               ("frontier_fuse_hiss", 1.0), ("frontier_collapse_rumble", 2.0), ("frontier_steam_hiss", 1.0),
               ("frontier_cart_rumble", 1.0)):
    _reg(_n, _d, True)

# the fourth set (the very hard maps): Doom Fortress, The Abyss, Tempest Tower, The Void
for _n, _d in (("abyss_lamp_dim", 1.0), ("abyss_lamp_out", 0.5), ("abyss_lamp_on", 0.6), ("abyss_vent_rumble", 1.0),
               ("abyss_vent_burst", 1.2), ("abyss_angler_growl", 1.0), ("abyss_angler_snap", 0.8),
               ("abyss_anchor_creak", 1.0), ("abyss_shrimp_click", 0.6), ("abyss_leviathan_moan", 2.6),
               ("abyss_surge_whoosh", 1.4), ("abyss_checkpoint", 1.2), ("abyss_finish", 3.0),
               ("tempest_gust_rise", 1.4), ("tempest_gust", 1.2), ("tempest_rod_charge", 1.4),
               ("tempest_lightning_strike", 1.2), ("tempest_scaffold_creak", 0.9), ("tempest_scaffold_fall", 1.6),
               ("tempest_load_bell", 1.0), ("tempest_gondola_start", 1.0), ("tempest_crane_horn", 1.4),
               ("tempest_ram_hiss", 1.0), ("tempest_driver_hiss", 1.0), ("tempest_thunder", 2.6),
               ("tempest_checkpoint", 1.2), ("tempest_finish_strike", 1.8), ("tempest_beacon", 2.4),
               ("void_phase_warn", 0.95), ("void_phase_swap", 0.6), ("void_rift_enter", 0.8), ("void_tumble_warn", 1.0),
               ("void_tumble_turn", 0.8), ("void_tumble_thud", 0.8), ("void_collapse_start", 2.0),
               ("void_fragment_crack", 0.6), ("void_fragment_fall", 1.0), ("void_checkpoint", 1.2), ("void_finish", 3.0),
               ("doom_press_warn", 0.9), ("doom_klaxon", 1.2), ("doom_lockdown", 1.2), ("doom_alarm_clear", 1.0),
               ("doom_catwalk_creak", 0.8), ("doom_catwalk_fall", 1.4), ("doom_pour_tilt", 1.2), ("doom_pour_splash", 1.2),
               ("doom_reactor_charge", 1.2), ("doom_reactor_pulse", 1.2), ("doom_vent_hiss", 1.0), ("doom_vent_blast", 1.2),
               ("doom_checkpoint", 1.2), ("doom_finish", 2.8)):
    _reg(_n, _d)
for _n, _d in (("abyss_current_loop", 2.0), ("abyss_surge_loop", 2.0),
               ("tempest_wind", 2.0), ("tempest_trolley", 1.0), ("tempest_gondola_motor", 1.0), ("tempest_crane_slew", 1.5),
               ("void_rift_hum", 2.0), ("void_collapse_rumble", 2.0),
               ("doom_pour_loop", 2.0), ("doom_reactor_hum", 2.0), ("doom_grate_buzz", 1.0), ("doom_gear_grind", 1.5)):
    _reg(_n, _d, True)

# the kit obstacles (docs/KIT_OBSTACLES.md) and the emotes / poses (each plays its emote_<id> clip)
for _n, _d in (("kit_barrel_load", 0.9), ("kit_barrel_fuse", 0.08), ("kit_barrel_fire", 1.0),
               ("kit_zipline_ready", 0.5), ("kit_zipline_grab", 0.5), ("kit_zipline_release", 0.5),
               ("kit_battery_fuse", 0.7), ("kit_battery_fire", 0.6), ("kit_log_reverse", 0.6),
               ("kit_seesaw_thunk", 0.6), ("kit_flipper_tell", 0.5), ("kit_flipper_swat", 0.5),
               ("kit_flipper_return", 0.6), ("kit_drawbridge_chains", 1.0), ("kit_drawbridge_raise", 1.2),
               ("kit_drawbridge_lower", 1.2), ("kit_drawbridge_thud", 0.8), ("kit_gapwall_warn", 0.8),
               ("kit_gapwall_slide", 1.0), ("kit_gapwall_thud", 0.6), ("kit_block_tell", 0.9),
               ("kit_block_slam", 0.8), ("kit_block_rise", 1.0), ("kit_hammer_tell", 0.9),
               ("kit_hammer_swing", 0.8), ("kit_hammer_park", 0.6),
               ("emote_wave", 0.9), ("emote_thumbsup", 0.5), ("emote_dance", 1.4), ("emote_bow", 1.0),
               ("emote_laugh", 1.2), ("emote_flex", 0.8), ("emote_spin", 0.9), ("emote_facepalm", 1.0),
               ("emote_taunt", 1.0), ("emote_sit", 0.6), ("emote_strongman", 0.9), ("emote_salute", 1.0),
               ("emote_hero", 1.4), ("emote_dab", 0.6), ("emote_rockstar", 1.2)):
    _reg(_n, _d)
for _n, _d in (("kit_zipline_whirr", 1.0), ("kit_log_roll", 1.5)):
    _reg(_n, _d, True)

# the Big Update's new worlds: Toybox Tumble, Olympus Rising, Pixel Panic (gen_toybox / gen_olympus / gen_arcade)
for _n, _d in (("toybox_checkpoint", 1.2), ("toybox_finish", 2.8), ("toybox_car_wind", 1.0), ("toybox_car_stop", 0.5),
               ("toybox_jack_tune", 1.1), ("toybox_jack_pop", 0.6), ("toybox_tell_tick", 0.12),
               ("toybox_tower_creak", 1.2), ("toybox_tower_fall", 1.2), ("toybox_tower_thud", 0.8),
               ("toybox_tower_lift", 1.0), ("toybox_tower_chime", 1.0),
               ("toybox_note_1", 0.9), ("toybox_note_2", 0.9), ("toybox_note_3", 0.9), ("toybox_note_4", 0.9),
               ("toybox_note_5", 0.9),
               ("olympus_checkpoint", 1.6), ("olympus_finish", 3.0), ("olympus_chariot_launch", 1.0),
               ("olympus_column_crack", 1.2), ("olympus_column_fall", 1.6), ("olympus_column_reform", 1.2),
               ("olympus_mirror_charge", 1.0), ("olympus_mirror_fire", 1.0), ("olympus_spirit_call", 1.1),
               ("olympus_spirit_gust", 1.5), ("olympus_tell_tick", 0.5),
               ("arcade_checkpoint", 1.2), ("arcade_finish", 2.4), ("arcade_boss_defeat", 1.4),
               ("arcade_block_tick", 0.1), ("arcade_block_land", 0.2), ("arcade_block_clear_warn", 1.0),
               ("arcade_block_clear", 0.6), ("arcade_block_drop", 0.5), ("arcade_paddle_ping", 0.25),
               ("arcade_ball_ping", 0.2), ("arcade_glitch_warn", 1.0), ("arcade_glitch_hop", 0.4),
               ("arcade_scroll_start", 1.0), ("arcade_boss_charge", 1.1), ("arcade_boss_blast", 0.8)):
    _reg(_n, _d)
for _n, _d in (("toybox_car_whirr", 1.0), ("olympus_chariot_wind", 2.0), ("olympus_mirror_hum", 1.0),
               ("olympus_wind_loop", 2.0), ("arcade_chomper_loop", 1.0), ("arcade_ball_hum", 1.0),
               ("arcade_scroll_rumble", 1.0)):
    _reg(_n, _d, True)
# Castle Siege (gen_siege) and Mushroom Hollow (gen_fungal): the mechanics' clips
for _n, _d in (("siege_boulder_launch", 1.0), ("siege_boulder_whistle", 1.1), ("siege_boulder_impact", 1.2),
               ("siege_ram_creak", 1.0), ("siege_ram_whoosh", 0.9), ("siege_ram_thud", 0.9),
               ("siege_oil_tilt", 1.2), ("siege_oil_pour", 1.2), ("siege_volley_horn", 1.6),
               ("siege_volley_whoosh", 1.2), ("siege_volley_hit", 0.9), ("siege_trebuchet_wind", 1.2),
               ("siege_trebuchet_throw", 1.0), ("siege_warning_horn", 0.8), ("siege_checkpoint", 2.0),
               ("siege_finish", 3.0),
               ("fungal_cap_boing", 0.6), ("fungal_checkpoint", 1.2), ("fungal_finish", 2.4),
               ("fungal_drip_plink", 0.4), ("fungal_drip_splash", 0.5), ("fungal_puff_swell", 1.1),
               ("fungal_puff_blow", 0.5), ("fungal_tell_tick", 0.1), ("fungal_frog_croak", 0.6)):
    _reg(_n, _d)
for _n, _d in (("siege_oil_loop", 2.0), ("fungal_puff_loop", 2.0), ("fungal_snail_squelch", 1.5)):
    _reg(_n, _d, True)


# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------
def dur(name):
    return CLIPS[name][0]


def rng(name):
    return ga.rng_for("world_" + name)


def ns(dur):
    return int(round(dur * SR))


def tv(dur):
    return ga.tvec(dur)


def unit(x):
    m = np.max(np.abs(x))
    return x / m if m > 0 else x


def band(x, lo=None, hi=None, order=2):
    return ga.fft_band(x, SR, lo, hi, order)


def cband(x, lo=None, hi=None, order=2):
    """Band filter over a loop (circular: the filtered loop still wraps seamlessly)."""
    return ga.fft_band(x, SR, lo, hi, order, circular=True)


def noise(r, n, lo=None, hi=None, order=2):
    return unit(band(r.standard_normal(n), lo, hi, order))


def cnoise(r, n, lo=None, hi=None, order=2):
    return unit(cband(r.standard_normal(n), lo, hi, order))


def tilt(x, db_per_oct, circular=False, ref=1000.0):
    """Spectral tilt (e.g. -3 dB/oct = pink) in the FFT domain."""
    pad = 0 if circular else int(0.03 * SR)
    xp = x if circular else np.concatenate([np.zeros(pad), x, np.zeros(pad)])
    spec = np.fft.rfft(xp)
    f = np.maximum(np.fft.rfftfreq(len(xp), 1.0 / SR), 20.0)
    y = np.fft.irfft(spec * (f / ref) ** (db_per_oct / 6.0206), len(xp))
    return y if circular else y[pad:pad + len(x)]


def fconv(a, b):
    """Linear convolution through the FFT."""
    n = len(a) + len(b) - 1
    m = 1 << (n - 1).bit_length()
    return np.fft.irfft(np.fft.rfft(a, m) * np.fft.rfft(b, m), m)[:n]


def cconv(x, ir):
    """Circular convolution (ir shorter than x): a reverb whose tail wraps round the loop."""
    h = np.zeros(len(x))
    h[:len(ir)] = ir[:len(x)]
    return np.fft.irfft(np.fft.rfft(x) * np.fft.rfft(h), len(x))


def svf(x, fc, q):
    return ga.svf_bandpass(x, np.broadcast_to(np.asarray(fc, dtype=float), x.shape).copy(), q, SR)


def csvf(x, fc, q):
    """Time-varying band-pass over a loop: run three periods, keep the settled middle one."""
    n = len(x)
    fc = np.broadcast_to(np.asarray(fc, dtype=float), x.shape)
    y = ga.svf_bandpass(np.tile(x, 3), np.tile(fc, 3), q, SR)
    return y[n:2 * n]


def env(t, a, tau):
    return ga.ad_env(t, a, tau)


def glide(f0, f1, t, dur):
    return ga.sweep(f0, f1, t, dur)


def tone(freq, t=None, phase=0.0):
    """Sine; `freq` may be a per-sample array (phase-accumulated, click-free glides)."""
    if np.ndim(freq) == 0:
        return np.sin(TAU * freq * t + phase)
    return ga.osc(freq, SR, phase)


def cyc(f, n):
    """Nearest frequency with a whole number of cycles in n samples (loop-safe)."""
    return max(round(f * n / SR), 1) * SR / n


def clfo(n, cycles, phase=0.0):
    return np.sin(TAU * cycles * np.arange(n) / n + phase)


def crand(r, n, max_cycles, power=1.0):
    """Smooth random modulation in -1..1 that repeats exactly every n samples."""
    x = np.zeros(n)
    i = np.arange(n) / n
    for c in range(1, max_cycles + 1):
        x += r.uniform(0.3, 1.0) / c ** power * np.sin(TAU * c * i + r.uniform(0, TAU))
    return unit(x)


def place(buf, t0, sig, gain=1.0):
    ga.place(buf, t0, sig, SR, gain)


def cplace(buf, t0, sig, gain=1.0):
    """place() that wraps round the end of a loop buffer."""
    n = len(buf)
    i0 = int(round(t0 * SR)) % n
    idx = (i0 + np.arange(len(sig))) % n
    np.add.at(buf, idx, sig * gain)


def taper(x, secs=0.004):
    """Short raised-cosine fade on the end of a building block, so a ring cut off by its
    buffer length never leaves a step when it is mixed into a longer clip."""
    k = min(int(secs * SR), len(x))
    if k > 1:
        x = x.copy()
        x[-k:] *= 0.5 + 0.5 * np.cos(np.pi * np.arange(k) / k)
    return x


def click(r, dur, lo, hi, tau):
    """Contact transient: band-passed noise with a very fast decay."""
    t = tv(dur)
    return noise(r, len(t), lo, hi) * np.exp(-t / tau)


def thud(t, f0, f1, glide_s, tau, harm=(0.35, 0.12), attack=0.002):
    """A mass hitting something: a pitched-down sine with a couple of harmonics."""
    f = glide(f0, f1, t, glide_s)
    x = tone(f)
    for k, a in enumerate(harm, start=2):
        x = x + a * tone(f * k) * np.exp(-t / (tau * 0.6))
    return taper(x * env(t, attack, tau))


def modes(t, spec, r=None, detune=0.0, hard=None):
    """Sum of exponentially damped sines [(freq, amp, tau)] - a struck object's modes.
    `hard`: strike hardness as a roll-off frequency (a soft hit barely excites high modes)."""
    x = np.zeros(len(t))
    for f, a, tau in spec:
        if r is not None:
            f *= 1.0 + r.uniform(-detune, detune)
        if f >= SR * 0.45:
            continue
        if hard:
            a /= np.sqrt(1.0 + (f / hard) ** 2)
        ph = r.uniform(0, TAU) if r is not None else 0.0
        x += a * np.sin(TAU * f * t + ph) * np.exp(-t / tau)
    return taper(x * np.minimum(t / 0.0006, 1.0))


BAR = (1.0, 2.756, 5.404, 8.933, 13.34)   # free-free beam mode ratios


def bar_modes(f1, tau1, amps=(1.0, 0.6, 0.4, 0.25, 0.15), damp=0.6):
    """Modes of a struck free bar (grating bars, brass rods, pawls)."""
    return [(f1 * k, a, tau1 / k ** damp) for k, a in zip(BAR, amps)]


def plate_modes(f11, aspect, tau11, count=10, damp=0.7, r=None):
    """Lowest modes of a simply supported rectangular plate: f ~ m^2 + (n/aspect)^2."""
    fs = sorted({(m * m + (k / aspect) ** 2) for m in range(1, 6) for k in range(1, 6)})[:count]
    base = 1.0 + 1.0 / aspect ** 2
    out = []
    for i, v in enumerate(fs):
        f = f11 * v / base
        a = 1.0 / (1.0 + 0.35 * i)
        if r is not None:
            a *= r.uniform(0.6, 1.2)
        out.append((f, a, tau11 * (f11 / f) ** damp))
    return out


def room_ir(r, rt, lo=150.0, hi=7000.0, dur=None, hf_damp=0.5):
    """Synthetic room / hall impulse response: noise whose high end decays faster."""
    dur = dur or rt * 1.1
    t = tv(dur)
    low = noise(r, len(t), lo, 1500.0) * np.exp(-6.91 * t / rt)
    high = noise(r, len(t), 1500.0, hi) * np.exp(-6.91 * t / (rt * hf_damp))
    ir = low + 0.7 * high
    ir *= np.minimum(t / 0.004, 1.0)
    return ir / np.sqrt(np.sum(ir ** 2))


def space(r, x, rt, mix, lo=150.0, hi=7000.0, hf_damp=0.5, predelay=0.006):
    ir = np.concatenate([np.zeros(int(predelay * SR)), room_ir(r, rt, lo, hi, hf_damp=hf_damp)])
    wet = fconv(x, ir)[:len(x)]
    return x + mix * wet * (np.max(np.abs(x)) / (np.max(np.abs(wet)) + 1e-9))


def grains(r, buf, count, t_lo, t_hi, f_lo, f_hi, tau_lo, tau_hi, gain=1.0, decay=None, wrap=False):
    """Scatter short band-passed noise grains (gravel, sparks, debris, crackle)."""
    for _ in range(count):
        t0 = r.uniform(t_lo, t_hi)
        c = np.exp(r.uniform(np.log(f_lo), np.log(f_hi)))
        tau = r.uniform(tau_lo, tau_hi)
        g = ga.grain(r, min(tau * 6.0, 0.08), c * 0.7, c * 1.4, tau)
        a = gain * r.uniform(0.2, 1.0) ** 1.5
        if decay:
            a *= np.exp(-(t0 - t_lo) / decay)
        (cplace if wrap else place)(buf, t0, g, a)


def bubble(f0, dur, tau, rise=0.6):
    """A bubble (Minnaert resonance): a decaying sine whose pitch rises as it forms."""
    t = tv(dur)
    f = f0 * (1.0 + rise * np.minimum(t / (tau * 3.0), 1.0))
    return taper(tone(f) * np.exp(-t / tau) * np.minimum(t / 0.0015, 1.0))


def whoosh(r, dur, f_lo, f_peak, f_end, t_peak, width, q=1.6):
    """Air moved past the ear: noise through a band that rises to the pass then falls (Doppler)."""
    t = tv(dur)
    k = np.where(t < t_peak, (t / t_peak) ** 1.5, 1.0)
    fc = np.where(t < t_peak, f_lo * (f_peak / f_lo) ** k,
                  f_peak * (f_end / f_peak) ** np.clip((t - t_peak) / max(dur - t_peak, 1e-3), 0, 1) ** 0.7)
    x = svf(r.standard_normal(len(t)), fc, q)
    e = np.exp(-0.5 * ((t - t_peak) / width) ** 2)
    e = np.where(t > t_peak, np.exp(-0.5 * ((t - t_peak) / (width * 1.4)) ** 2), e)
    return unit(x) * e


def creak(r, dur, rate_fn, spec):
    """Stick-slip: a jittered impulse train (rate_fn(u) per second, u = 0..1) through damped
    resonances [(freq, amp, tau)] - wood or fibre groaning, stone grinding on stone."""
    n = ns(dur)
    imp = np.zeros(n)
    pos = 0.0
    while pos < dur:
        imp[min(int(pos * SR), n - 1)] = r.uniform(0.5, 1.0)
        pos += 1.0 / max(rate_fn(pos / dur), 1.0) * r.uniform(0.85, 1.15)
    return taper(unit(fconv(imp, modes(tv(0.08), spec))[:n]))


def reson(fc, f, q):
    """Resonance gain (1 at fc, bandwidth fc / q); fc and f may be arrays."""
    return 1.0 / (1.0 + ((f - fc) / (fc / q)) ** 2)


def buzz_wave(f0, n, harmonics=24, tilt_pow=1.0, even=1.0):
    """Band-limited buzzy periodic wave (a saw-like sum of sines)."""
    t = np.arange(n) / SR
    x = np.zeros(n)
    for k in range(1, harmonics + 1):
        if f0 * k > SR * 0.42:
            break
        a = 1.0 / k ** tilt_pow * (even if k % 2 == 0 else 1.0)
        x += a * np.sin(TAU * f0 * k * t)
    return unit(x)


# ---------------------------------------------------------------------------
# output
# ---------------------------------------------------------------------------
LOG = []

# Footsteps and landings are loudness-matched across the maps instead of peak-normalised
# (a clicky glass step and a soft grass step at the same peak differ by ~8 dB to the ear):
# each is scaled to an A-weighted short-term loudness, never above the -3 dBFS peak.
STEP_LOUD_DB = -25.0
LAND_LOUD_DB = -23.0


def a_weight(f):
    f2 = np.maximum(f, 1.0) ** 2
    ra = (12194.0 ** 2 * f2 ** 2) / ((f2 + 20.6 ** 2) * np.sqrt((f2 + 107.7 ** 2) * (f2 + 737.9 ** 2)) *
                                     (f2 + 12194.0 ** 2))
    return ra / 0.7943


def loudness(x, win=0.08):
    """A-weighted RMS of the loudest `win` seconds (dB)."""
    y = np.fft.irfft(np.fft.rfft(x) * a_weight(np.fft.rfftfreq(len(x), 1.0 / SR)), len(x))
    k = int(win * SR)
    best = max(np.sqrt(np.mean(y[i:i + k] ** 2)) for i in range(0, max(len(y) - k, 1), k // 4))
    return ga.db(best)


def levelled_target(name):
    if name.startswith("step_"):
        return STEP_LOUD_DB
    if name.startswith("land_") and name != "land_heavy":
        return LAND_LOUD_DB
    return None


def _fit(name, x):
    want = ns(CLIPS[name][0])
    if len(x) < want:
        x = np.concatenate([x, np.zeros(want - len(x))])
    return x[:want]


def save(name, x, fin=0.002, fout=0.02):
    x = _fit(name, np.asarray(x, dtype=float))
    x = band(x, 18.0, None, 2)          # DC / subsonic out first, so the fades end on zero
    x = ga.fade(x - np.mean(x), SR, fin, fout)
    x *= 10.0 ** (PEAK_DB / 20.0) / np.max(np.abs(x))
    target = levelled_target(name)
    if target is not None:
        x *= min(10.0 ** ((target - loudness(x)) / 20.0), 1.0)
    ga.write_wav(name, x, SR)
    LOG.append(name)
    print("  %-24s %5.2f s  peak %6.2f dBFS  rms %6.1f dB" % (
        name + ".wav", len(x) / SR, ga.db(np.max(np.abs(x))), ga.db(np.sqrt(np.mean(x ** 2)))))


def save_loop(name, x):
    """Loops: no fades (they would put a dip on the seam); mean removal and gain are seam-safe."""
    x = _fit(name, np.asarray(x, dtype=float))
    x = ga.norm_peak(x)
    ga.write_wav(name, x, SR, loop=True)
    LOG.append(name)
    print("  %-24s %5.2f s  loop  rms %6.1f dB  wrap step %.4f" % (
        name + ".wav", len(x) / SR, ga.db(np.sqrt(np.mean(x ** 2))), abs(x[0] - x[-1])))


# ===========================================================================
# per-map footsteps and landings
# ===========================================================================
# One material model per map, shared by the step (k = 0) and the landing (k = 1)
# so they sound like the same floor.  Each variant re-rolls the modes, the noise
# and the heel/toe timing.

def surface_hit(theme, r, k, dur):
    n = ns(dur)
    t = tv(dur)
    x = np.zeros(n)
    toe_t = r.uniform(0.024, 0.04)  # heel then toe (a step); a landing is both feet at once
    toe_g = r.uniform(0.35, 0.55) * (1.0 - 0.6 * k)

    def both(sig, gain=1.0, spread=True):
        place(x, 0.0, sig, gain)
        if spread and toe_g > 0.05:
            place(x, toe_t, sig, gain * toe_g)

    if theme == "gardens":
        # soft earth under grass: a damped pat, loose soil, a rustle of blades
        body = thud(t, r.uniform(125, 150), 62, 0.05, 0.022 + 0.03 * k, harm=(0.2, 0.05))
        soil = noise(r, n, 120, 900) * env(t, 0.002, 0.016 + 0.03 * k)
        both(body + 0.55 * soil, 1.0)
        rustle = np.zeros(n)
        grains(r, rustle, int(30 + 70 * k), 0.0, 0.06 + 0.12 * k, 2500, 9000, 0.0015, 0.005, 1.0,
               decay=0.03 + 0.06 * k)
        grains(r, rustle, int(6 + 22 * k), 0.004, 0.05 + 0.15 * k, 500, 2200, 0.003, 0.009, 0.8,
               decay=0.04 + 0.06 * k)   # clods and pebbles
        x += 0.42 * unit(rustle)
        x = band(x, None, 9000)
        if k:
            place(x, 0.0, thud(t, 90, 42, 0.1, 0.07, harm=(0.25,)), 0.9)
    elif theme == "foundry":
        # steel grating over a void: a hard click, ringing bars, the hollow box under it,
        # and the grating chattering in its frame
        f1 = r.uniform(360, 460)
        ring = modes(t, bar_modes(f1, 0.055 + 0.05 * k), r, 0.03, hard=5000 + 3000 * k)
        cav = thud(t, r.uniform(185, 225), r.uniform(165, 190), 0.05, 0.045 + 0.05 * k, harm=(0.3,))
        both(click(r, dur, 2000, 11000, 0.0012) * 0.9 + 0.55 * ring + 0.6 * cav
             + 0.5 * thud(t, 130, 70, 0.03, 0.018))
        for j in range(int(1 + 5 * k + r.integers(0, 2))):
            tj = r.uniform(0.012, 0.035) + j * r.uniform(0.018, 0.04)
            rat = modes(tv(0.08), bar_modes(f1 * r.uniform(0.97, 1.03), 0.02), r, 0.04, hard=4000)
            place(x, tj, rat + 0.5 * click(r, 0.08, 1500, 8000, 0.001), 0.28 * np.exp(-j * 0.4))
        if k:
            place(x, 0.0, thud(t, 95, 45, 0.12, 0.12), 0.8)
            x = space(r, x, 0.9, 0.35, 200, 6000)
    elif theme == "balance":
        # painted steel deck (the paint deadens it) over timber bearers
        plate = modes(t, plate_modes(r.uniform(220, 260), 1.6, 0.035 + 0.04 * k, 8, 0.8, r), r, 0.02, hard=3500)
        wood = modes(t, [(r.uniform(480, 560), 1.0, 0.012), (r.uniform(850, 960), 0.6, 0.009),
                         (r.uniform(1350, 1550), 0.35, 0.006)], r, 0.0)
        both(click(r, dur, 1500, 6500, 0.0011) * 0.7 + 0.5 * plate + 0.45 * wood
             + 0.8 * thud(t, 135, 72, 0.035, 0.022 + 0.02 * k))
        if k:
            place(x, 0.0, thud(t, 100, 48, 0.1, 0.09), 0.75)
            grains(r, x, 10, 0.01, 0.12, 800, 3000, 0.002, 0.006, 0.12, decay=0.05)
            x = space(r, x, 0.6, 0.2, 200, 5000)
    elif theme == "clockwork":
        # waxed oak boards with brass inlay: a warm knock and the faintest brass shimmer
        oak = modes(t, [(r.uniform(205, 235), 1.0, 0.03), (r.uniform(440, 500), 0.7, 0.02),
                        (r.uniform(760, 830), 0.45, 0.014), (r.uniform(1200, 1320), 0.3, 0.009),
                        (r.uniform(2100, 2400), 0.15, 0.005)], r, 0.0)
        brass = modes(t, bar_modes(r.uniform(1150, 1400), 0.12 + 0.1 * k, (1.0, 0.5, 0.3, 0.15, 0.08), 0.5), r, 0.01)
        both(click(r, dur, 1000, 5000, 0.0018) * 0.7 + 0.8 * oak + 0.1 * brass
             + 0.7 * thud(t, 150, 88, 0.03, 0.028 + 0.03 * k))
        if k:
            place(x, 0.0, thud(t, 105, 55, 0.08, 0.1), 0.7)
            place(x, 0.0, modes(t, bar_modes(r.uniform(900, 1100), 0.3), r, 0.01), 0.1)
        x = space(r, x, 0.7 + 0.4 * k, 0.16 + 0.1 * k, 200, 6000)
    elif theme == "reef":
        # wet sand that sucks at the foot, brittle coral crumbs, water in the pores; muffled
        suck = svf(r.standard_normal(n), glide(r.uniform(850, 1000), 320, t, 0.06 + 0.05 * k), 2.2)
        suck = unit(suck) * env(t, 0.004, 0.03 + 0.04 * k)
        body = thud(t, r.uniform(105, 125), 55, 0.05, 0.03 + 0.04 * k, harm=(0.2,))
        both(0.75 * suck + body)
        crunch = np.zeros(n)
        grains(r, crunch, int(8 + 20 * k), 0.004, 0.05 + 0.1 * k, 1200, 4500, 0.0015, 0.004, 1.0, decay=0.04)
        x += 0.35 * unit(crunch)
        for _ in range(int(2 + 5 * k)):
            place(x, r.uniform(0.01, 0.07 + 0.15 * k), bubble(r.uniform(900, 2200), 0.03, 0.006), 0.12)
        x = band(x, None, 3000, 3)
        if k:
            place(x, 0.0, thud(t, 80, 38, 0.12, 0.09), 0.8)
    elif theme == "orbital":
        # thin deck plate over a service void: bright ring, a hollow boom, station air
        plate = modes(t, plate_modes(r.uniform(290, 340), 1.3, 0.09 + 0.08 * k, 10, 0.55, r), r, 0.02,
                      hard=7000 + 3000 * k)
        tink = modes(t, bar_modes(r.uniform(2100, 2500), 0.05, (1.0, 0.4, 0.2, 0.1, 0.05)), r, 0.02)
        boom = thud(t, r.uniform(110, 125), 92, 0.05, 0.07 + 0.08 * k, harm=(0.3, 0.1))
        both(click(r, dur, 3000, 13000, 0.0009) * 0.8 + 0.45 * plate + 0.18 * tink + 0.7 * boom)
        if k:
            place(x, 0.0, thud(t, 85, 40, 0.12, 0.12), 0.7)
            for j in range(3):
                place(x, 0.03 + 0.03 * j + r.uniform(0, 0.01),
                      modes(tv(0.1), plate_modes(r.uniform(300, 360), 1.3, 0.03, 6, 0.6, r), r, 0.03, hard=6000),
                      0.2 * 0.6 ** j)
        x = space(r, x, 0.5 + 0.4 * k, 0.22, 250, 9000, 0.6)
    elif theme == "ascent":
        # hard glass over a neon panel: a sharp tick, a high glassy ring, a thin buzz
        glass = modes(t, plate_modes(r.uniform(650, 760), 1.4, 0.07 + 0.08 * k, 10, 0.35, r), r, 0.01,
                      hard=9000)
        body = thud(t, 170, 95, 0.025, 0.018 + 0.02 * k, harm=(0.2,))
        both(click(r, dur, 2500, 15000, 0.0007) * 1.0 + 0.3 * glass + 0.55 * body)
        tb = tv(0.03)
        buzz = noise(r, len(tb), 1500, 7000) * (0.5 + 0.5 * np.sin(TAU * 120 * tb)) ** 6 * env(tb, 0.001, 0.008)
        place(x, 0.003, buzz, 0.25 + 0.15 * k)
        if k:
            place(x, 0.0, thud(t, 110, 55, 0.08, 0.08), 0.65)
            place(x, 0.02, modes(tv(dur - 0.02), plate_modes(r.uniform(900, 1000), 1.4, 0.12, 8, 0.3, r), r, 0.01), 0.12)
        x = space(r, x, 0.5, 0.12, 400, 10000, 0.7)
    elif theme == "xeno":
        # spongy alien moss over a chitin crust: the moss squashes (air squeezed out of its pores, a
        # soft wet squelch whose band rises as it compresses), thin chitin plates crunch under it with
        # small hollow pings, and the pores breathe out a faint hiss
        squash = svf(r.standard_normal(n), glide(r.uniform(260, 320), r.uniform(900, 1100), t, 0.05 + 0.04 * k), 2.0)
        squash = unit(squash) * env(t, 0.003 + 0.004 * k, 0.025 + 0.035 * k)
        body = thud(t, r.uniform(115, 135), 70, 0.05, 0.03 + 0.04 * k, harm=(0.25,))
        both(1.0 * squash + 0.7 * body)
        crunch = np.zeros(n)
        grains(r, crunch, int(6 + 18 * k), 0.006, 0.04 + 0.08 * k, 1800, 6500, 0.0008, 0.0025, 1.0,
               decay=0.03 + 0.03 * k)
        for _ in range(int(2 + 4 * k)):
            ping = modes(tv(0.06), [(r.uniform(1500, 2600), 1.0, 0.012), (r.uniform(3400, 4800), 0.5, 0.006)], r, 0.0)
            place(crunch, r.uniform(0.004, 0.03 + 0.06 * k), ping, r.uniform(0.3, 0.8))
        x += 0.6 * unit(crunch)
        x += 0.15 * noise(r, n, 1500, 6000) * env(t, 0.008, 0.02 + 0.03 * k)
        x = band(x, None, 8000)
        if k:
            # the low-gravity sponge gives, then springs back with a soft rising "bwum"
            place(x, 0.0, thud(t, 95, 45, 0.1, 0.08), 0.6)
            place(x, 0.02, taper(tone(glide(70, 105, t, 0.12)) * env(t, 0.02, 0.08)), 0.45)
    elif theme == "volcano":
        # loose cinder (scoria) over basalt: porous clinkers crunch and grind, with a few glassy
        # ticks of vesicular glass among them; the basalt under them gives a firm, dead stone knock
        stone = modes(t, [(r.uniform(300, 360), 1.0, 0.012), (r.uniform(610, 700), 0.7, 0.009),
                          (r.uniform(1050, 1200), 0.45, 0.006), (r.uniform(1700, 1950), 0.3, 0.004)], r, 0.0)
        body = thud(t, r.uniform(140, 160), 80, 0.03, 0.02 + 0.03 * k, harm=(0.3, 0.1))
        grit = noise(r, n, 700, 5000) * env(t, 0.002, 0.012 + 0.02 * k)
        both(0.9 * body + 0.5 * stone + 0.45 * grit)
        crunch = np.zeros(n)
        grains(r, crunch, int(25 + 60 * k), 0.0, 0.05 + 0.12 * k, 900, 7000, 0.001, 0.004, 1.0,
               decay=0.025 + 0.05 * k)
        for _ in range(int(3 + 6 * k)):
            ping = modes(tv(0.03), [(r.uniform(3500, 6500), 1.0, 0.004), (r.uniform(7000, 9500), 0.4, 0.002)], r, 0.0)
            place(crunch, r.uniform(0.003, 0.04 + 0.1 * k), ping, r.uniform(0.2, 0.6))
        x += 0.8 * unit(crunch)
        x = band(x, None, 10000)
        if k:
            place(x, 0.0, thud(t, 100, 55, 0.1, 0.08, harm=(0.3,)), 0.6)
            # clinkers kicked loose by the impact settle a moment later
            for _ in range(4):
                clack = modes(tv(0.08), [(r.uniform(900, 1600), 1.0, 0.01), (r.uniform(2200, 3400), 0.5, 0.005)], r, 0.0)
                place(x, r.uniform(0.05, 0.2), clack + 0.4 * click(r, 0.08, 1500, 7000, 0.001), r.uniform(0.08, 0.2))
            x += 0.06 * noise(r, n, 1500, 6000) * env(t, 0.02, 0.1)   # a puff of ash
    elif theme == "glacier":
        # crunchy packed snow over hard ice: the snow compresses in a quick run of crunches (cold
        # grains fracturing, with the faint tonal squeak of very cold snow) over a dull pat, and the
        # ice under it answers with a hard, glassy tick
        body = thud(t, r.uniform(120, 140), 70, 0.04, 0.025 + 0.03 * k, harm=(0.2,))
        ice = modes(t, [(r.uniform(1800, 2300), 1.0, 0.02), (r.uniform(3900, 4700), 0.6, 0.012),
                        (r.uniform(6500, 7800), 0.3, 0.006)], r, 0.0)
        both(0.8 * body + 0.2 * ice + 0.3 * click(r, dur, 2500, 12000, 0.0008))
        span = 0.05 + 0.1 * k
        crunch = np.zeros(n)
        grains(r, crunch, int(40 + 90 * k), 0.0, span, 500, 4000, 0.001, 0.004, 1.0, decay=0.03 + 0.05 * k)
        squeak = np.zeros(n)
        for _ in range(int(3 + 5 * k)):
            ts = tv(0.02)
            sq = tone(r.uniform(900, 1800) * (1.0 + 0.3 * ts / 0.02)) * env(ts, 0.002, 0.006)
            place(squeak, r.uniform(0.0, span), taper(sq), r.uniform(0.3, 1.0))
        x += 0.8 * unit(crunch) + 0.15 * unit(squeak)
        x = band(x, None, 11000)
        if k:
            place(x, 0.0, thud(t, 95, 50, 0.1, 0.08), 0.6)
            x += 0.1 * noise(r, n, 1500, 6000) * env(t, 0.01, 0.08)   # a puff of powder
    elif theme == "desert":
        # soft sand over sandstone: the sole shushes into the sand (a soft, dry hiss that swells as
        # the foot slides and settles) with fine grains trickling off it, a muffled pat, and under the
        # sand the sandstone gives a gritty scuff and a short, dead knock
        shh = noise(r, n, 600, 5000) * env(t, 0.008 + 0.006 * k, 0.03 + 0.04 * k)
        body = thud(t, r.uniform(110, 130), 62, 0.05, 0.03 + 0.03 * k, harm=(0.2,))
        stone = modes(t, [(r.uniform(420, 500), 1.0, 0.008), (r.uniform(900, 1050), 0.6, 0.006),
                          (r.uniform(1600, 1900), 0.35, 0.004)], r, 0.0)
        grit = noise(r, n, 1500, 7000) * env(t, 0.001, 0.006)
        both(0.7 * shh + 0.8 * body + 0.3 * stone + 0.25 * grit)
        trickle = np.zeros(n)
        grains(r, trickle, int(25 + 60 * k), 0.01, 0.08 + 0.15 * k, 2500, 9000, 0.0006, 0.002, 1.0,
               decay=0.04 + 0.06 * k)
        x += 0.35 * unit(trickle)
        x = band(x, None, 9000)
        if k:
            place(x, 0.0, thud(t, 90, 48, 0.1, 0.08), 0.6)
            x += 0.3 * noise(r, n, 800, 6000) * env(t, 0.01, 0.12)   # sand thrown up
    elif theme == "manor":
        # old oak boards laid over stone: a hollow, dry knock with the board's low modes (it is loose
        # on its joists, so it rings a little longer and lower than the clockwork's waxed oak), grit
        # scuffing on the flags beneath, often a short creak as the board flexes, in a stone hall
        oak = modes(t, [(r.uniform(150, 185), 1.0, 0.04), (r.uniform(330, 390), 0.75, 0.025),
                        (r.uniform(640, 740), 0.45, 0.016), (r.uniform(1100, 1300), 0.25, 0.01)], r, 0.0)
        body = thud(t, r.uniform(125, 145), 70, 0.04, 0.03 + 0.03 * k, harm=(0.3, 0.1))
        grit = noise(r, n, 1200, 6000) * env(t, 0.002, 0.008)
        both(click(r, dur, 900, 5000, 0.0015) * (0.5 + 0.3 * k) + (0.8 - 0.3 * k) * oak + (0.8 - 0.4 * k) * body
             + (0.2 + 0.3 * k) * grit)
        if r.random() < 0.6 + 0.4 * k:
            cl = 0.07 + 0.12 * k
            cr = creak(r, cl, lambda u: 60.0 + 90.0 * np.sin(np.pi * u),
                       [(r.uniform(420, 520), 1.0, 0.012), (r.uniform(900, 1100), 0.6, 0.008),
                        (r.uniform(1700, 2000), 0.3, 0.005)])
            place(x, r.uniform(0.03, 0.05), cr * np.sin(np.pi * np.arange(len(cr)) / len(cr)), 0.22 + 0.1 * k)
        if k:
            place(x, 0.0, thud(t, 95, 48, 0.1, 0.1), 0.4)
            grains(r, x, 14, 0.01, 0.12, 700, 3500, 0.002, 0.006, 0.1, decay=0.05)   # dust off the boards
        x = space(r, x, 1.1 + 0.4 * k, 0.2 + 0.1 * k, 150, 5000, 0.45)
    elif theme == "armada":
        # a wet wooden deck in the rain: a plank knock, the film of water slapping and splashing
        # away from the sole in droplets, and a faint suck as the boot lifts
        plank = modes(t, [(r.uniform(260, 320), 1.0, 0.02), (r.uniform(560, 660), 0.7, 0.014),
                          (r.uniform(1000, 1200), 0.4, 0.009), (r.uniform(1600, 1900), 0.2, 0.006)], r, 0.0)
        body = thud(t, r.uniform(130, 150), 75, 0.035, 0.025 + 0.03 * k, harm=(0.3,))
        slap = noise(r, n, 500, 5000) * env(t, 0.001, 0.012 + 0.015 * k)
        both(0.6 * plank + 0.8 * body + 0.6 * slap)
        splash = np.zeros(n)
        grains(r, splash, int(12 + 40 * k), 0.004, 0.05 + 0.12 * k, 1500, 7000, 0.001, 0.004, 1.0, decay=0.03 + 0.05 * k)
        for _ in range(int(3 + 8 * k)):
            place(splash, r.uniform(0.01, 0.06 + 0.15 * k), bubble(r.uniform(1100, 3000), 0.03, 0.005, 0.8),
                  r.uniform(0.3, 0.8))
        x += 0.45 * unit(splash)
        tl = tv(0.05)
        suck = svf(r.standard_normal(len(tl)), glide(500, 1400, tl, 0.04), 3.0) * env(tl, 0.01, 0.015)
        place(x, r.uniform(0.07, 0.09), taper(unit(suck)), 0.12)
        x = band(x, None, 10000)
        if k:
            place(x, 0.0, thud(t, 100, 50, 0.1, 0.09), 0.7)
            x += 0.2 * noise(r, n, 800, 6000) * env(t, 0.004, 0.06)   # the puddle thrown up
    elif theme == "candy":
        # sugar-crusted candy over something soft: the crust crunches in a spray of bright, glassy
        # sugar crystals, the soft body under it squishes (a wet band rising as it squashes) and
        # gives a springy little rebound
        squish = svf(r.standard_normal(n), glide(r.uniform(380, 450), r.uniform(1300, 1600), t, 0.04 + 0.04 * k), 2.5)
        squish = unit(squish) * env(t, 0.003 + 0.003 * k, 0.02 + 0.03 * k)
        body = thud(t, r.uniform(140, 165), 85, 0.04, 0.025 + 0.03 * k, harm=(0.25,))
        both(0.8 * squish + 0.7 * body)
        crunch = np.zeros(n)
        grains(r, crunch, int(35 + 80 * k), 0.0, 0.035 + 0.08 * k, 2000, 9500, 0.0006, 0.0025, 1.0, decay=0.02 + 0.04 * k)
        for _ in range(int(3 + 5 * k)):
            ping = modes(tv(0.03), [(r.uniform(4000, 7000), 1.0, 0.004), (r.uniform(8000, 11000), 0.4, 0.002)], r, 0.0)
            place(crunch, r.uniform(0.0, 0.03 + 0.06 * k), ping, r.uniform(0.2, 0.6))
        x += 0.7 * unit(crunch)
        boing = taper(tone(glide(150, 190, t, 0.05)) * env(t, 0.01, 0.03 + 0.05 * k) *
                      (1.0 + 0.3 * np.sin(TAU * 11.0 * t)))
        place(x, 0.015, boing, 0.25 + 0.15 * k)
        x = band(x, None, 11000)
        if k:
            place(x, 0.0, thud(t, 100, 55, 0.1, 0.08), 0.55)
            place(x, 0.03, taper(tone(glide(85, 130, t, 0.12)) * env(t, 0.02, 0.08) * (1.0 + 0.4 * np.sin(TAU * 8.0 * t))), 0.4)
    elif theme == "carrier":
        # the flight deck: inch-thick steel under a gritty non-skid coating. It barely rings (the
        # plate is thick and welded down), so it is a hard, dense knock: a boot-heel click, a scratchy
        # non-skid scuff (a dense rasp of grit), and a low, heavy body with just a hint of the plate
        plate = modes(t, plate_modes(r.uniform(170, 200), 1.8, 0.02 + 0.03 * k, 8, 0.9, r), r, 0.02, hard=2500)
        body = thud(t, r.uniform(150, 175), 90, 0.025, 0.02 + 0.03 * k, harm=(0.35, 0.12))
        both(click(r, dur, 2000, 10000, 0.001) * 0.45 + 0.3 * plate + 0.6 * body)
        rasp = np.zeros(n)
        grains(r, rasp, int(60 + 80 * k), 0.0, 0.03 + 0.05 * k, 1200, 7000, 0.0004, 0.0015, 1.0, decay=0.015 + 0.03 * k)
        x += 0.5 * unit(rasp)
        x += 0.3 * noise(r, n, 2000, 8000) * env(t, 0.002, 0.012 + 0.01 * k)   # the sole scuffing
        x = band(x, None, 11000)
        if k:
            place(x, 0.0, thud(t, 90, 42, 0.12, 0.1, harm=(0.3,)), 0.45)
            # the hull's deep answer through the deck
            place(x, 0.005, modes(tv(dur - 0.005), plate_modes(r.uniform(70, 85), 2.0, 0.12, 5, 0.8, r), r, 0.02, hard=400), 0.2)
    elif theme == "sakura":
        # polished cypress boards of a temple floor, raised over the stone (a little hollow under
        # them): a tight, warm knock and a soft scuff of a sock on the polish. Now and then the
        # floor's clamps chirp underfoot (a nightingale floor), and a landing reaches the stone below
        wood = modes(t, [(r.uniform(240, 280), 1.0, 0.025), (r.uniform(520, 600), 0.7, 0.016),
                         (r.uniform(900, 1020), 0.45, 0.01), (r.uniform(1500, 1700), 0.25, 0.006)], r, 0.0)
        hollow = thud(t, r.uniform(160, 185), r.uniform(140, 160), 0.04, 0.035 + 0.03 * k, harm=(0.25,))
        both(click(r, dur, 1200, 6000, 0.0012) * 0.5 + 0.8 * wood + 0.6 * hollow + 0.5 * thud(t, 140, 80, 0.03, 0.02))
        x += 0.12 * noise(r, n, 1500, 7000) * env(t, 0.003, 0.02)
        if r.random() < 0.35 + 0.4 * k:
            tc = tv(0.05)
            chirp = tone(glide(r.uniform(1500, 1900), r.uniform(2300, 2800), tc, 0.03)) * np.sin(np.pi * tc / 0.05) ** 2
            place(x, r.uniform(0.02, 0.04), taper(chirp), 0.08 + 0.05 * k)
        x = band(x, None, 10000)
        if k:
            place(x, 0.0, thud(t, 100, 50, 0.1, 0.09), 0.6)
            place(x, 0.0, modes(t, [(r.uniform(320, 380), 1.0, 0.012), (r.uniform(700, 800), 0.6, 0.008),
                                    (r.uniform(1200, 1400), 0.35, 0.005)], r, 0.0), 0.25)
        x = space(r, x, 0.9 + 0.3 * k, 0.15 + 0.08 * k, 200, 7000)
    elif theme == "jungle":
        # mossy temple stone under leaf litter: the stone's dull, dead knock, muffled by a damp pad of
        # moss (a soft squelch), and leaves and twigs crackling on top
        stone = modes(t, [(r.uniform(330, 390), 1.0, 0.01), (r.uniform(680, 780), 0.6, 0.007),
                          (r.uniform(1150, 1300), 0.35, 0.005)], r, 0.0)
        body = thud(t, r.uniform(125, 145), 70, 0.04, 0.025 + 0.03 * k, harm=(0.25,))
        moss = svf(r.standard_normal(n), glide(r.uniform(300, 380), r.uniform(800, 950), t, 0.04 + 0.03 * k), 2.0)
        moss = unit(moss) * env(t, 0.003, 0.018 + 0.025 * k)
        both(0.9 * body + 0.35 * stone + 0.5 * moss)
        litter = np.zeros(n)
        grains(r, litter, int(30 + 70 * k), 0.0, 0.06 + 0.12 * k, 1200, 8000, 0.0012, 0.004, 1.0, decay=0.03 + 0.06 * k)
        grains(r, litter, int(4 + 10 * k), 0.005, 0.05 + 0.1 * k, 400, 1500, 0.003, 0.008, 0.6, decay=0.04)   # twigs
        x += 0.5 * unit(litter)
        x = band(x, None, 9000)
        if k:
            place(x, 0.0, thud(t, 95, 45, 0.1, 0.09), 0.7)
            x += 0.08 * noise(r, n, 2000, 7000) * env(t, 0.02, 0.1)   # leaves settling
    elif theme == "frontier":
        # the roof boards of a wooden boxcar, dry and dusty: a plank knock over the hollow car (its
        # body booms low), grit scuffing under the boot, and often a loose roofwalk board clacking
        plank = modes(t, [(r.uniform(280, 330), 1.0, 0.018), (r.uniform(600, 690), 0.65, 0.012),
                          (r.uniform(1050, 1200), 0.4, 0.008), (r.uniform(1800, 2100), 0.2, 0.005)], r, 0.0)
        boom = thud(t, r.uniform(115, 135), r.uniform(95, 110), 0.05, 0.05 + 0.06 * k, harm=(0.3, 0.1))
        both(click(r, dur, 1200, 6000, 0.0015) * 0.6 + 0.7 * plank + 0.6 * boom + 0.5 * thud(t, 150, 85, 0.03, 0.02))
        grit = np.zeros(n)
        grains(r, grit, int(20 + 40 * k), 0.0, 0.04 + 0.06 * k, 1500, 7500, 0.0008, 0.003, 1.0, decay=0.02 + 0.03 * k)
        x += 0.3 * unit(grit)
        if r.random() < 0.3 + 0.5 * k:
            board = modes(tv(0.06), [(r.uniform(700, 900), 1.0, 0.008), (r.uniform(1500, 1800), 0.5, 0.005)], r, 0.0)
            place(x, r.uniform(0.03, 0.06), board, 0.2 + 0.1 * k)
        x = band(x, None, 10000)
        if k:
            place(x, 0.0, thud(t, 90, 45, 0.12, 0.12, harm=(0.3,)), 0.6)
            x += 0.1 * noise(r, n, 600, 4000) * env(t, 0.01, 0.15)   # a puff of dust
    elif theme == "neon":
        # a wet steel rooftop: a sheet-metal panel's dull ring (damped by the water on it), the boot
        # slapping the puddle and droplets spraying off; the landing splashes and booms the panel
        plate = modes(t, plate_modes(r.uniform(230, 270), 1.5, 0.03 + 0.03 * k, 8, 0.7, r), r, 0.02, hard=4000)
        body = thud(t, r.uniform(135, 155), 80, 0.03, 0.022 + 0.03 * k, harm=(0.3,))
        slap = noise(r, n, 600, 6000) * env(t, 0.001, 0.01 + 0.015 * k)
        both(click(r, dur, 2000, 9000, 0.001) * 0.35 + 0.45 * plate + 0.7 * body + 0.6 * slap)
        splash = np.zeros(n)
        grains(r, splash, int(16 + 45 * k), 0.004, 0.05 + 0.12 * k, 1500, 8000, 0.001, 0.004, 1.0, decay=0.03 + 0.05 * k)
        for _ in range(int(2 + 6 * k)):
            place(splash, r.uniform(0.01, 0.05 + 0.15 * k), bubble(r.uniform(1200, 3200), 0.03, 0.004, 0.8), r.uniform(0.3, 0.8))
        x += 0.5 * unit(splash)
        x = band(x, None, 11000)
        if k:
            place(x, 0.0, thud(t, 95, 45, 0.1, 0.09), 0.6)
            x += 0.2 * noise(r, n, 800, 7000) * env(t, 0.004, 0.06)   # the puddle thrown up
        x = space(r, x, 0.5, 0.12, 300, 8000)
    elif theme == "doom":
        # iron grating bolted over riveted steel beams: a dark, heavy clank of thick bars, the riveted
        # plate under them booming, scale and grit crunching, and the grating rattling in its frame
        f1 = r.uniform(230, 290)
        bars = modes(t, bar_modes(f1, 0.05 + 0.05 * k, (1.0, 0.5, 0.3, 0.15, 0.08)), r, 0.03, hard=3500 + 2000 * k)
        plate = modes(t, plate_modes(r.uniform(140, 170), 1.8, 0.05 + 0.05 * k, 8, 0.7, r), r, 0.02, hard=2500)
        body = thud(t, r.uniform(120, 140), 65, 0.04, 0.03 + 0.04 * k, harm=(0.3, 0.1))
        both(click(r, dur, 1500, 8000, 0.0012) * 0.7 + 0.5 * bars + 0.35 * plate + 0.8 * body)
        grit = np.zeros(n)
        grains(r, grit, int(12 + 30 * k), 0.0, 0.03 + 0.06 * k, 1500, 7000, 0.0006, 0.002, 1.0, decay=0.02 + 0.03 * k)
        x += 0.2 * unit(grit)
        if r.random() < 0.4 + 0.5 * k:
            rat = modes(tv(0.08), bar_modes(f1 * r.uniform(0.97, 1.03), 0.02), r, 0.04, hard=3000)
            place(x, r.uniform(0.025, 0.05), rat + 0.4 * click(r, 0.08, 1500, 7000, 0.001), 0.2 + 0.1 * k)
        x = band(x, None, 9000)
        if k:
            place(x, 0.0, thud(t, 85, 40, 0.12, 0.13, harm=(0.3,)), 0.8)
        x = space(r, x, 1.0 + 0.4 * k, 0.2 + 0.1 * k, 150, 5000)
    elif theme == "abyss":
        # soft silt over a bed of broken shells, deep under water: the foot sinks in with a muffled puff
        # (silt billowing up), a soft body, shells crunching and cracking beneath; all of it dulled
        puff = svf(r.standard_normal(n), glide(r.uniform(500, 650), r.uniform(180, 230), t, 0.06 + 0.04 * k), 1.6)
        puff = unit(puff) * env(t, 0.006, 0.035 + 0.05 * k)
        body = thud(t, r.uniform(95, 115), 55, 0.05, 0.03 + 0.04 * k, harm=(0.2,))
        both(0.7 * puff + body)
        shells = np.zeros(n)
        grains(r, shells, int(10 + 30 * k), 0.006, 0.05 + 0.1 * k, 1500, 6000, 0.0008, 0.003, 1.0, decay=0.03 + 0.04 * k)
        for _ in range(int(1 + 2 * k + r.integers(0, 2))):
            sh = modes(tv(0.04), [(r.uniform(1800, 2600), 1.0, 0.004), (r.uniform(3500, 4800), 0.5, 0.0025)], r, 0.0)
            place(shells, r.uniform(0.008, 0.04 + 0.05 * k), sh, r.uniform(0.4, 0.9))
        x += 0.4 * unit(shells)
        x = band(x, None, 4500, 3)
        if k:
            place(x, 0.0, thud(t, 75, 36, 0.12, 0.1), 0.8)
            x += 0.15 * noise(r, n, 150, 900) * env(t, 0.03, 0.12)   # the silt settling
    elif theme == "tempest":
        # a rain-soaked steel girder (an I-beam ringing low, damped by the water on it), the boot slapping
        # the film of water, droplets thrown off, and the curtain wall's glass beside it ticking
        f1 = r.uniform(310, 380)
        beam = modes(t, bar_modes(f1, 0.07 + 0.06 * k, (1.0, 0.55, 0.3, 0.15, 0.08), 0.7), r, 0.02, hard=4000 + 2000 * k)
        body = thud(t, r.uniform(130, 150), 75, 0.03, 0.025 + 0.03 * k, harm=(0.3,))
        slap = noise(r, n, 500, 6000) * env(t, 0.001, 0.01 + 0.015 * k)
        glass = modes(t, plate_modes(r.uniform(700, 820), 1.3, 0.02 + 0.02 * k, 8, 0.4, r), r, 0.01, hard=8000)
        both(click(r, dur, 2000, 10000, 0.0009) * 0.4 + 0.45 * beam + 0.7 * body + 0.55 * slap + 0.12 * glass)
        splash = np.zeros(n)
        grains(r, splash, int(16 + 40 * k), 0.004, 0.05 + 0.12 * k, 1500, 8000, 0.001, 0.004, 1.0, decay=0.03 + 0.05 * k)
        for _ in range(int(1 + 5 * k)):
            place(splash, r.uniform(0.01, 0.05 + 0.15 * k), bubble(r.uniform(1200, 3200), 0.03, 0.004, 0.8), r.uniform(0.3, 0.8))
        x += 0.45 * unit(splash)
        x = band(x, None, 11000)
        if k:
            place(x, 0.0, thud(t, 95, 45, 0.1, 0.1), 0.6)
            place(x, 0.0, modes(t, bar_modes(f1 * 0.5, 0.15, (1.0, 0.5, 0.25, 0.1, 0.05), 0.7), r, 0.02, hard=3000), 0.2)
            x += 0.2 * noise(r, n, 800, 7000) * env(t, 0.004, 0.06)   # the water thrown up
        x = space(r, x, 0.4, 0.1, 300, 8000)
    elif theme == "void":
        # polished marble floating over nothing: a dense, hard stone knock, the hollow under the slab (a
        # ringing cavity tone), a cool glassy shimmer from its veins, in a vast, empty space
        marble = modes(t, [(r.uniform(520, 600), 1.0, 0.018), (r.uniform(1150, 1300), 0.7, 0.012),
                           (r.uniform(1900, 2150), 0.45, 0.008), (r.uniform(3000, 3400), 0.25, 0.005)], r, 0.0)
        hollow = thud(t, r.uniform(210, 250), r.uniform(195, 230), 0.03, 0.06 + 0.05 * k, harm=(0.3, 0.12))
        glass = modes(t, plate_modes(r.uniform(1100, 1300), 1.2, 0.08 + 0.08 * k, 8, 0.3, r), r, 0.01, hard=10000)
        both(click(r, dur, 2500, 12000, 0.0008) * 0.8 + 0.6 * marble + 0.5 * hollow + 0.12 * glass
             + 0.5 * thud(t, 150, 90, 0.03, 0.02))
        x = band(x, None, 12000)
        if k:
            place(x, 0.0, thud(t, 100, 50, 0.1, 0.09), 0.6)
        x = space(r, x, 1.6 + 0.6 * k, 0.22 + 0.08 * k, 250, 9000, 0.6)
    elif theme == "toybox":
        # a plastic brick knocked onto pine boards: a bright plastic tick, the hollow board under it (a
        # little box-like boom), the foot's thud, and a rattle of loose bricks (k: the heavier landing)
        tick = modes(t, [(r.uniform(2400, 2800), 1.0, 0.004), (r.uniform(4200, 4700), 0.5, 0.0025)], r, 0.0)
        board = modes(t, bar_modes(r.uniform(250, 300), 0.04 + 0.04 * k, (1.0, 0.6, 0.3, 0.15), 0.6), r, 0.02, hard=2500)
        body = thud(t, r.uniform(110, 130), 60, 0.04, 0.03 + 0.04 * k, harm=(0.25,))
        both(click(r, dur, 2000, 9000, 0.001) * 0.6 + 0.55 * tick + 0.45 * board + 0.7 * body)
        bricks = np.zeros(n)
        grains(r, bricks, int(6 + 14 * k), 0.0, 0.05 + 0.1 * k, 1800, 6000, 0.0008, 0.002, 1.0, decay=0.02 + 0.03 * k)
        x += 0.25 * unit(bricks)
        x = band(x, None, 9000)
        if k:
            place(x, 0.0, thud(t, 95, 45, 0.1, 0.08), 0.7)
        x = space(r, x, 0.6, 0.15, 200, 8000)
    elif theme == "fungal":
        # a spongy toadstool cap underfoot: a soft, wet squish as the cap folds and springs back, a damped
        # body beneath, and the leaf litter crunching quietly (k: the landing flattens the cap)
        squish = svf(r.standard_normal(n), glide(r.uniform(380, 480), r.uniform(160, 210), t, 0.08 + 0.05 * k), 1.2)
        squish = unit(squish) * env(t, 0.008, 0.05 + 0.06 * k)
        body = thud(t, r.uniform(90, 110), 50, 0.06, 0.04 + 0.05 * k, harm=(0.2,))
        both(0.8 * squish + 0.6 * body)
        litter = np.zeros(n)
        grains(r, litter, int(8 + 24 * k), 0.01, 0.06 + 0.1 * k, 1200, 5000, 0.0008, 0.003, 1.0, decay=0.03 + 0.04 * k)
        x += 0.3 * unit(litter)
        x = band(x, None, 4500, 3)
        if k:
            place(x, 0.0, thud(t, 80, 40, 0.1, 0.1), 0.6)
        x = space(r, x, 0.5, 0.1, 200, 4000)
    elif theme == "carnival":
        # boardwalk planks of loose pine: a hollow, springy slap of a plank, its nail knocking on the joist
        # beneath, a scatter of grit (k: the landing sends the planks clattering)
        f1 = r.uniform(200, 240)
        plank = modes(t, bar_modes(f1, 0.06 + 0.05 * k, (1.0, 0.5, 0.3, 0.15), 0.6), r, 0.02, hard=3000 + 1500 * k)
        body = thud(t, r.uniform(120, 140), 65, 0.04, 0.03 + 0.04 * k, harm=(0.3,))
        both(click(r, dur, 2500, 9000, 0.0009) * 0.5 + 0.5 * plank + 0.7 * body)
        grit = np.zeros(n)
        grains(r, grit, int(10 + 30 * k), 0.0, 0.05 + 0.1 * k, 1500, 7000, 0.0008, 0.002, 1.0, decay=0.03 + 0.04 * k)
        x += 0.25 * unit(grit)
        x = band(x, None, 8000)
        if k:
            place(x, 0.0, thud(t, 90, 42, 0.1, 0.09), 0.7)
        x = space(r, x, 0.5, 0.12, 150, 6000)
    elif theme == "olympus":
        # polished marble steps in a sunlit temple: a crisp, dry click, a clear ring from the stone, a soft
        # body beneath and the open air (k: the landing rings longer)
        ring = modes(t, [(r.uniform(780, 880), 1.0, 0.03 + 0.03 * k), (r.uniform(1950, 2150), 0.4, 0.015),
                         (r.uniform(3100, 3400), 0.2, 0.008)], r, 0.0)
        body = thud(t, r.uniform(140, 165), 80, 0.03, 0.03 + 0.03 * k, harm=(0.2,))
        both(click(r, dur, 2500, 11000, 0.0008) * 0.9 + 0.35 * ring + 0.5 * body)
        x = band(x, None, 10000)
        if k:
            place(x, 0.0, thud(t, 100, 50, 0.1, 0.09), 0.5)
        x = space(r, x, 1.2 + 0.5 * k, 0.2 + 0.08 * k, 250, 9000, 0.6)
    elif theme == "dino":
        # packed earth under the ferns: a soft, heavy thump that sinks into the soil, the grass swishing as
        # its stems part, and a twig snapping under the weight (k: the landing crushes the ferns)
        body = thud(t, r.uniform(85, 105), 40, 0.1, 0.07 + 0.06 * k, harm=(0.3, 0.1))
        soil = noise(r, n, 100, 800) * env(t, 0.004, 0.03 + 0.05 * k)
        both(body + 0.5 * soil)
        swish = np.zeros(n)
        grains(r, swish, int(14 + 40 * k), 0.0, 0.08 + 0.12 * k, 1000, 6000, 0.001, 0.004, 1.0, decay=0.03 + 0.06 * k)
        x += 0.35 * unit(swish)
        if r.random() < 0.5 + 0.4 * k:
            twig = modes(tv(0.05), bar_modes(r.uniform(1400, 1800), 0.012, (1.0, 0.4), 0.7), r, 0.02, hard=3000)
            place(x, r.uniform(0.02, 0.07), twig, 0.2 + 0.1 * k)
        x = band(x, None, 7000)
        if k:
            place(x, 0.0, thud(t, 70, 35, 0.12, 0.12), 0.8)
        x = space(r, x, 0.6, 0.12, 120, 5000)
    elif theme == "arcane":
        # an old library floor, planks laid over a stone flag: the boards' dry creak, a hollow wood knock,
        # the flag's stone thud beneath, and dust sifting from the shelves (k: the landing shakes the dust down)
        creak = svf(r.standard_normal(n), glide(r.uniform(900, 1100), r.uniform(500, 650), t, 0.1), 6.0)
        creak = unit(creak) * env(t, 0.002, 0.04 + 0.04 * k)
        board = modes(t, bar_modes(r.uniform(200, 250), 0.05 + 0.04 * k, (1.0, 0.6, 0.3), 0.6), r, 0.02, hard=2500)
        stone = thud(t, r.uniform(160, 190), 90, 0.03, 0.02 + 0.03 * k, harm=(0.2,))
        both(0.35 * creak + 0.5 * board + 0.7 * stone + 0.4 * click(r, dur, 1500, 7000, 0.0012))
        dust = np.zeros(n)
        grains(r, dust, int(4 + 12 * k), 0.01, 0.05 + 0.1 * k, 2000, 8000, 0.0008, 0.002, 1.0, decay=0.02 + 0.03 * k)
        x += 0.15 * unit(dust)
        x = band(x, None, 8000)
        if k:
            place(x, 0.0, thud(t, 85, 40, 0.1, 0.1), 0.6)
        x = space(r, x, 1.0 + 0.4 * k, 0.18 + 0.08 * k, 150, 6000)
    elif theme == "arcade":
        # a pixel tap on a rubber mat: a short, bright square-wave bleep, its pitch stepping down, and the
        # plastic click of the contact (k: the heavier landing bleeps lower)
        f = r.uniform(780, 1000) * (1.0 - 0.12 * k)
        sq = sum(np.sin(TAU * f * h * t) / h for h in (1, 3, 5, 7, 9) if h * f < 0.45 * SR)
        blip = sq * env(t, 0.0005, 0.012 + 0.01 * k)
        both(0.7 * blip + 0.4 * click(r, dur, 2500, 9000, 0.0009))
        x = band(x, None, 9000)
        if k:
            place(x, 0.0, thud(t, 95, 45, 0.1, 0.09), 0.5)
    elif theme == "siege":
        # a flagstone of the castle yard, cut stone bedded in mortar: a dull slap of the slab, a crisp chip off
        # its edge, grit crunching in the joint, and the stone's low thud beneath (k: the landing cracks it)
        slab = modes(t, plate_modes(r.uniform(330, 380), 1.5, 0.02 + 0.02 * k, 6, 0.6, r), r, 0.01, hard=5000)
        body = thud(t, r.uniform(100, 120), 55, 0.04, 0.04 + 0.04 * k, harm=(0.2, 0.08))
        both(click(r, dur, 1200, 7000, 0.0013) * 0.8 + 0.4 * slab + 0.8 * body)
        grit = np.zeros(n)
        grains(r, grit, int(10 + 30 * k), 0.0, 0.04 + 0.08 * k, 1500, 7000, 0.0006, 0.002, 1.0, decay=0.02 + 0.03 * k)
        x += 0.35 * unit(grit)
        x = band(x, None, 9000)
        if k:
            place(x, 0.0, thud(t, 80, 38, 0.12, 0.12), 0.8)
        x = space(r, x, 0.9 + 0.4 * k, 0.18 + 0.07 * k, 200, 6000)
    return x


STEP_THEMES = None   # --themes=a,b: regenerate only those surfaces' footsteps and landings


def gen_steps():
    for th in THEMES:
        if STEP_THEMES and th not in STEP_THEMES:
            continue
        for i in range(1, 5):
            name = "step_%s_%d" % (th, i)
            save(name, surface_hit(th, rng(name), 0.0, STEP_LEN), fin=0.0008, fout=0.03)
        for i in range(1, 4):
            name = "land_%s_%d" % (th, i)
            save(name, surface_hit(th, rng(name), 1.0, LAND_LEN), fin=0.0008, fout=0.08)


# ===========================================================================
# movement
# ===========================================================================
def panel_knock(r, t, weight=1.0):
    """The wall-run panel: a dark composite slab on a frame - hollow, a little metallic."""
    plate = modes(t, plate_modes(r.uniform(260, 300), 2.2, 0.03 + 0.02 * weight, 8, 0.7, r), r, 0.02,
                  hard=3000 + 2000 * weight)
    cav = thud(t, r.uniform(150, 175), 135, 0.03, 0.035 + 0.02 * weight, harm=(0.25,))
    return 0.45 * plate + 0.7 * cav + 0.5 * click(r, len(t) / SR, 1200, 7000, 0.0012)


def crackle(r, dur, count, lo=3000, hi=11000, wrap=False, n=None):
    """Spark crackle: sparse sharp ticks (the panel's cyan sparks, a live beam)."""
    buf = np.zeros(n if n is not None else ns(dur))
    for _ in range(count):
        t0 = r.uniform(0, dur)
        tk = tv(0.004)
        g = noise(r, len(tk), lo, hi) * np.exp(-tk / r.uniform(0.0003, 0.0009))
        (cplace if wrap else place)(buf, t0, g, r.uniform(0.2, 1.0) ** 2)
    return buf


def gen_wall():
    for i in range(1, 5):
        name = "wallstep_%d" % i
        r = rng(name)
        t = tv(dur(name))
        x = panel_knock(r, t, 0.6) + 0.35 * crackle(r, 0.03, 5, n=len(t))
        save(name, x, fin=0.0008, fout=0.03)

    name = "wallrun_latch"
    r = rng(name)
    t = tv(dur(name))
    x = panel_knock(r, t, 1.2)
    zing = tone(glide(700, 2100, t, 0.09)) * env(t, 0.004, 0.06)
    zing += 0.3 * tone(glide(1400, 4200, t, 0.09)) * env(t, 0.004, 0.04)
    x += 0.22 * zing + 0.45 * crackle(r, 0.12, 22, n=len(t))
    x += 0.35 * unit(svf(r.standard_normal(len(t)), glide(1500, 4500, t, 0.2), 3.0)) * env(t, 0.02, 0.08)
    save(name, x, fin=0.0008, fout=0.08)

    # wall kick: a heavy push-off from the panel, sparks, and the whoosh of being thrown off it
    for i in range(1, 4):
        name = "wallkick_%d" % i
        r = rng(name)
        t = tv(dur(name))
        x = 1.1 * panel_knock(r, t, 1.6) + 0.6 * thud(t, 120, 55, 0.05, 0.05)
        x += 0.4 * crackle(r, 0.08, 18, n=len(t))
        x += 0.7 * whoosh(r, dur(name), r.uniform(500, 700), r.uniform(3000, 3800), 1100, 0.1, 0.05)
        save(name, x, fin=0.0008, fout=0.1)

    # mantle: the hands slap onto the lip, a scramble of feet, and Volt's servos hauling up
    for i in range(1, 4):
        name = "mantle_%d" % i
        r = rng(name)
        t = tv(dur(name))
        x = np.zeros(len(t))
        th = tv(0.12)
        hand = modes(th, bar_modes(r.uniform(1050, 1300), 0.025), r, 0.03, hard=6000)
        hand = 0.5 * hand + click(r, 0.12, 300, 3500, 0.005) + 0.5 * thud(th, 190, 110, 0.02, 0.015)
        place(x, 0.0, hand, 1.0)
        place(x, r.uniform(0.035, 0.06), hand, 0.7)
        for ts in (r.uniform(0.13, 0.16), r.uniform(0.22, 0.26)):
            tsv = tv(0.05)
            scuff = noise(r, len(tsv), 700, 5000) * env(tsv, 0.004, 0.012)
            place(x, ts, scuff + 0.5 * thud(tsv, 150, 100, 0.02, 0.012), 0.4)
        tw = tv(0.3)
        f = glide(250, 640, tw, 0.28) * (1.0 + 0.01 * np.sin(TAU * 38 * tw))
        servo = (tone(f) + 0.45 * tone(2 * f) + 0.2 * tone(3 * f)) * np.sin(np.pi * tw / 0.3) ** 1.5
        place(x, 0.05, servo, 0.16)
        place(x, 0.34, thud(tv(0.1), 140, 80, 0.03, 0.02), 0.45)
        save(name, x, fin=0.0008, fout=0.08)

    name = "land_heavy"
    r = rng(name)
    t = tv(dur(name))
    x = 1.2 * thud(t, 72, 30, 0.2, 0.16, harm=(0.4, 0.15))
    x += 0.7 * noise(r, len(t), 150, 700) * env(t, 0.003, 0.05)
    x += 0.5 * click(r, 0.8, 800, 7000, 0.003)
    grains(r, x, 26, 0.02, 0.45, 400, 3200, 0.003, 0.012, 0.35, decay=0.15)
    # the knees soak it up: a short descending servo groan
    tg = tv(0.22)
    fg = glide(520, 190, tg, 0.2)
    groan = (tone(fg) + 0.5 * tone(fg * 2.01) + 0.25 * tone(fg * 3.02)) * env(tg, 0.01, 0.08)
    place(x, 0.03, groan, 0.18)
    save(name, x, fin=0.0008, fout=0.15)

    # boost strip launch: an electric zing that climbs, a whoosh and a shove
    name = "boost"
    r = rng(name)
    t = tv(dur(name))
    f = glide(480, 2500, t, 0.13) * (1.0 + 0.012 * np.sin(TAU * 11 * t) * np.minimum(t / 0.15, 1.0))
    fm = 1.0 + 0.004 * np.sin(TAU * f * 1.5 * t)
    z = tone(f * fm) + 0.4 * tone(2 * f) * np.exp(-t / 0.1) + 0.2 * tone(3.01 * f) * np.exp(-t / 0.06)
    z += 0.25 * tone(f * 1.005) + 0.25 * tone(f * 0.995)
    z *= env(t, 0.006, 0.16)
    x = 0.5 * z + 0.8 * whoosh(r, 0.6, 700, 5200, 1500, 0.12, 0.07) + 0.6 * thud(t, 110, 60, 0.04, 0.04)
    x += 0.3 * crackle(r, 0.15, 25, n=len(t))
    save(name, x, fin=0.0008, fout=0.12)


def gen_movement_loops():
    # air rush: the wind of your own speed - broadband turbulence, a buffeting low end, a
    # thin whistle that wanders, all breathing with slow gusts
    name = "air_rush"
    r = rng(name)
    n = ns(dur(name))
    body = cnoise(r, n, 120, 5500, 1)
    body = unit(tilt(body, -3.0, circular=True))
    gust = 0.62 + 0.38 * crand(r, n, 7)
    low = cnoise(r, n, 28, 170, 2) * (0.6 + 0.4 * crand(r, n, 24))
    whistle_fc = 1150 * (1.0 + 0.18 * crand(r, n, 4))
    whistle = unit(csvf(r.standard_normal(n), whistle_fc, 14.0)) * (0.5 + 0.5 * crand(r, n, 5))
    flutter = cnoise(r, n, 3500, 9000) * (0.5 + 0.5 * crand(r, n, 30)) ** 2
    x = body * gust + 0.75 * low + 0.12 * whistle + 0.12 * flutter
    save_loop(name, x)

    # wall-run scrape: friction hiss with stick-slip jitter, a faint squeal and the sparks
    name = "wallrun_scrape"
    r = rng(name)
    n = ns(dur(name))
    hiss = cnoise(r, n, 1600, 7500) * (0.55 + 0.45 * crand(r, n, 70, 0.3))
    grind = cnoise(r, n, 150, 700) * (0.6 + 0.4 * crand(r, n, 40, 0.5))
    squeal = unit(csvf(r.standard_normal(n), cyc(2600, n) * (1 + 0.04 * crand(r, n, 3)), 22.0))
    x = hiss + 0.5 * grind + 0.07 * squeal + 0.8 * crackle(r, dur(name), 60, wrap=True, n=n)
    save_loop(name, x)

    # ice slide: a smooth hiss of the sole on ice, a little skate rumble, rare squeaks and ticks
    name = "ice_slide"
    r = rng(name)
    n = ns(dur(name))
    hiss = cnoise(r, n, 2500, 10000) * (0.8 + 0.2 * crand(r, n, 9))
    shh = cnoise(r, n, 600, 2200) * (0.7 + 0.3 * crand(r, n, 6))
    rum = cnoise(r, n, 90, 320)
    squeak = unit(csvf(r.standard_normal(n), 3400 * (1 + 0.06 * crand(r, n, 2)), 28.0)) * \
        np.maximum(crand(r, n, 3), 0.0) ** 2
    ticks = crackle(r, dur(name), 14, 5000, 12000, wrap=True, n=n)
    x = hiss + 0.45 * shh + 0.3 * rum + 0.1 * squeak + 0.5 * ticks
    save_loop(name, x)


# ===========================================================================
# lasers, blink platforms, crushers, pistons, sweepers, pendulums
# ===========================================================================
def hum_stack(n, f0, count, tilt_pow=1.1, even=1.4, r=None):
    """Mains / transformer hum: a harmonic stack, even harmonics strong (magnetostriction)."""
    t = np.arange(n) / SR
    x = np.zeros(n)
    for k in range(1, count + 1):
        if f0 * k > SR * 0.4:
            break
        a = 1.0 / k ** tilt_pow * (even if k % 2 == 0 else 1.0)
        x += a * np.sin(TAU * f0 * k * t + (r.uniform(0, TAU) if r is not None else 0.0))
    return unit(x)


def gen_lasers():
    # the beam's hum: 110 Hz transformer stack, a crackling electric buzz locked to it,
    # a thin high whine beating slowly, a gentle 2 Hz wobble
    name = "laser_hum"
    r = rng(name)
    n = ns(dur(name))
    t = np.arange(n) / SR
    f0 = cyc(110, n)
    hum = hum_stack(n, f0, 16, 1.0, 1.5, r)
    pulse = (0.5 + 0.5 * np.sin(TAU * f0 * t)) ** 8
    buzz = cnoise(r, n, 2000, 9000) * pulse
    whine = np.sin(TAU * cyc(3520, n) * t) + np.sin(TAU * cyc(3524, n) * t)
    x = hum * (0.9 + 0.1 * clfo(n, 2)) + 0.35 * unit(buzz) + 0.04 * whine
    x += 0.25 * crackle(r, dur(name), 30, wrap=True, n=n)
    save_loop(name, x)

    name = "laser_on"
    r = rng(name)
    t = tv(dur(name))
    f = np.where(t < 0.05, glide(150, 2400, t, 0.05), 2400 * (880 / 2400) ** np.clip((t - 0.05) / 0.08, 0, 1))
    zap = (tone(f) + 0.5 * tone(f * 1.5) * np.exp(-t / 0.05)) * env(t, 0.002, 0.07)
    crack = click(r, 0.4, 1000, 12000, 0.006)
    boom = thud(t, 95, 45, 0.06, 0.06)
    hum = hum_stack(len(t), 110, 12, 1.0, 1.5, r) * env(t, 0.02, 0.12)
    sizzle = noise(r, len(t), 3000, 9000) * (0.5 + 0.5 * np.sin(TAU * 110 * t)) ** 6 * env(t, 0.01, 0.12)
    x = 0.45 * zap + 0.8 * crack + 0.6 * boom + 0.4 * hum + 0.5 * unit(sizzle) + 0.4 * crackle(r, 0.25, 25, n=len(t))
    save(name, x, fin=0.0008, fout=0.1)

    name = "laser_off"
    r = rng(name)
    t = tv(dur(name))
    f = glide(1300, 55, t, 0.26)
    down = (tone(f) + 0.4 * tone(2 * f) + 0.2 * tone(3 * f)) * env(t, 0.003, 0.1)
    x = 0.6 * down + 0.6 * click(r, 0.35, 1500, 9000, 0.003) + 0.35 * crackle(r, 0.12, 14, n=len(t))
    x += 0.3 * noise(r, len(t), 2500, 8000) * env(t, 0.005, 0.05)
    save(name, x, fin=0.0008, fout=0.08)

    # blink platforms: materialise / dematerialise shimmer-zaps and the flicker tick
    name = "blink_appear"
    r = rng(name)
    t = tv(dur(name))
    sweep_n = unit(svf(r.standard_normal(len(t)), glide(400, 6000, t, 0.12), 3.0)) * env(t, 0.06, 0.04)
    x = 0.5 * sweep_n
    for t0, m in ((0.07, 84), (0.1, 91)):
        tt = tv(0.3)
        fm = ga.mtof(m)
        c = tone(fm * (1 + 0.003 * np.sin(TAU * 7 * tt))) + 0.3 * tone(fm * 2.01, tt) * np.exp(-tt / 0.05)
        place(x, t0, c * env(tt, 0.003, 0.09), 0.35)
    place(x, 0.1, thud(tv(0.15), 190, 105, 0.03, 0.03), 0.6)
    save(name, x, fin=0.002, fout=0.08)

    name = "blink_vanish"
    r = rng(name)
    t = tv(dur(name))
    # a descending tone quantised into steps (a glitchy dissolve)
    steps = np.floor(t / 0.028)
    f = 1700 * (280 / 1700) ** np.clip(steps * 0.028 / 0.3, 0, 1)
    g = (tone(f) + 0.35 * tone(f * 2.0)) * env(t, 0.004, 0.14)
    disp = unit(svf(r.standard_normal(len(t)), glide(5500, 600, t, 0.3), 2.5)) * env(t, 0.005, 0.12)
    x = 0.4 * g + 0.5 * disp
    for _ in range(14):
        tt = tv(0.12)
        place(x, r.uniform(0.0, 0.3), tone(r.uniform(2500, 6000), tt) * env(tt, 0.001, 0.02), 0.1)
    save(name, x, fin=0.001, fout=0.1)

    name = "blink_tick"
    r = rng(name)
    t = tv(dur(name))
    x = (tone(2200, t) + 0.4 * tone(4410, t)) * env(t, 0.0008, 0.008) + 0.3 * click(r, 0.06, 3000, 9000, 0.0008)
    save(name, x, fin=0.0005, fout=0.02)


def gen_crusher_piston():
    # the press shudders: a stick-slip groan of the guides, rattling chains, a rumble building
    name = "crusher_shudder"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    imp = np.zeros(n)
    pos = 0.0
    while pos < 0.45:
        imp[min(int(pos * SR), n - 1)] = r.uniform(0.5, 1.0)
        pos += 1.0 / (38.0 + 30.0 * pos) * r.uniform(0.85, 1.15)
    k = modes(tv(0.05), [(180, 1.0, 0.012), (430, 0.6, 0.008), (950, 0.35, 0.005), (1900, 0.2, 0.003)])
    groan = fconv(imp, k)[:n]
    rattle = noise(r, n, 800, 3200) * (0.5 + 0.5 * np.sign(np.sin(TAU * 31 * t)))
    rumble = noise(r, n, 35, 200)
    x = unit(groan) + 0.3 * unit(band(rattle, None, 5000)) + 0.6 * rumble
    x *= np.minimum(t / 0.3, 1.0) ** 1.3 * 0.7 + 0.3
    save(name, x, fin=0.004, fout=0.04)

    # the slam: crack, a sub boom, the ringing steel block, floor thump, debris and dust
    name = "crusher_slam"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = 0.9 * click(r, dur(name), 500, 9000, 0.008)
    x += 1.2 * thud(t, 60, 27, 0.25, 0.35, harm=(0.45, 0.2))
    x += 0.45 * modes(t, plate_modes(140, 1.4, 0.3, 12, 0.6, r), r, 0.02, hard=3000)
    # the four steel teeth on its underside clang against the floor plate
    for j in range(4):
        place(x, r.uniform(0.0, 0.006), modes(t, bar_modes(r.uniform(520, 700), 0.16), r, 0.02, hard=6000), 0.12)
    x += 0.7 * noise(r, n, 60, 450) * env(t, 0.002, 0.15)
    grains(r, x, 38, 0.03, 0.7, 400, 3200, 0.003, 0.012, 0.3, decay=0.25)
    x += 0.12 * noise(r, n, 1000, 6000) * env(t, 0.05, 0.4)
    x = space(r, x, 1.1, 0.3, 120, 5000)
    save(name, x, fin=0.0008, fout=0.3)

    # and hauls itself back up: a hydraulic whine climbing, the valve's hiss, fluid gurgle
    name = "crusher_rise"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    f = glide(150, 265, t, 0.85) * (1.0 + 0.01 * np.sin(TAU * 29 * t))
    whine = (tone(f) + 0.55 * tone(2 * f) + 0.3 * tone(3 * f) + 0.15 * tone(5 * f))
    whine *= np.minimum(t / 0.08, 1.0) * np.clip((dur(name) - t) / 0.25, 0, 1)
    hiss = noise(r, n, 2000, 7500) * env(t, 0.01, 0.2)
    gurgle = noise(r, n, 90, 420) * (0.5 + 0.5 * np.sin(TAU * 13 * t + 3 * np.sin(TAU * 3 * t)))
    x = 0.4 * unit(whine) + 0.45 * hiss + 0.3 * unit(gurgle) * np.minimum(t / 0.1, 1.0)
    save(name, x, fin=0.01, fout=0.2)

    # piston: the pneumatic valve fires, the ram hits its end stop, then vents steam on retract
    name = "piston_fire"
    r = rng(name)
    t = tv(dur(name))
    blast = noise(r, len(t), 600, 8000) * env(t, 0.003, 0.05)
    x = blast + 0.8 * thud(t, 130, 60, 0.04, 0.045) + 0.35 * modes(t, [(2800, 1.0, 0.005), (4100, 0.5, 0.003)])
    x += 0.4 * noise(r, len(t), 200, 900) * env(t, 0.01, 0.06)
    save(name, x, fin=0.0008, fout=0.06)

    name = "piston_clank"
    r = rng(name)
    t = tv(dur(name))
    x = 0.55 * modes(t, bar_modes(255, 0.16), r, 0.02, hard=5000) + 0.9 * click(r, 0.45, 800, 8000, 0.002)
    x += 1.0 * thud(t, 115, 52, 0.05, 0.06)
    for j in range(2):
        place(x, 0.02 + 0.025 * j, modes(tv(0.1), bar_modes(255 * r.uniform(1.8, 2.2), 0.02), r, 0.03), 0.15)
    x = space(r, x, 0.6, 0.15)
    save(name, x, fin=0.0008, fout=0.1)

    name = "piston_retract"
    r = rng(name)
    t = tv(dur(name))
    hiss = noise(r, len(t), 1500, 9000) * env(t, 0.02, 0.22) * (0.75 + 0.25 * np.sin(TAU * 17 * t))
    servo = tone(glide(210, 150, t, 0.6)) * env(t, 0.05, 0.25)
    x = hiss + 0.12 * servo
    save(name, x, fin=0.01, fout=0.2)


def gen_swings():
    for i in range(1, 4):
        name = "sweep_whoosh_%d" % i
        r = rng(name)
        t = tv(dur(name))
        tp = r.uniform(0.2, 0.24)
        w = whoosh(r, 0.5, r.uniform(280, 350), r.uniform(1900, 2500), 550, tp, 0.06)
        e = np.exp(-0.5 * ((t - tp) / 0.06) ** 2)
        sizzle = noise(r, len(t), 4000, 9500) * (0.5 + 0.5 * np.sin(TAU * 100 * t)) ** 6 * e
        low = noise(r, len(t), 70, 260) * e
        save(name, w + 0.35 * unit(sizzle) + 0.4 * low, fin=0.01, fout=0.1)
    for i in range(1, 3):
        name = "pendulum_whoosh_%d" % i
        r = rng(name)
        t = tv(dur(name))
        tp = r.uniform(0.33, 0.38)
        w = whoosh(r, dur(name), 140, r.uniform(800, 1000), 240, tp, 0.12, q=1.2)
        e = np.exp(-0.5 * ((t - tp) / 0.12) ** 2)
        vw = tone(np.interp(t, [0, tp, dur(name)], [70, 96, 58])) * e
        save(name, w + 0.5 * vw + 0.3 * noise(r, len(t), 50, 180) * e, fin=0.01, fout=0.15)


# ===========================================================================
# surfaces, wind, motors, portals, props
# ===========================================================================
def gen_surfaces():
    # conveyor: a 50 Hz motor, its rotor whine, rollers clicking under the belt, belt hiss
    name = "conveyor_hum"
    r = rng(name)
    n = ns(dur(name))
    t = np.arange(n) / SR
    motor = hum_stack(n, cyc(50, n), 12, 1.2, 1.3, r) * (0.9 + 0.1 * clfo(n, 6))
    whine = np.sin(TAU * cyc(610, n) * t) * (0.7 + 0.3 * clfo(n, 3))
    rollers = np.zeros(n)
    for j in range(10):
        tk = tv(0.03)
        c = modes(tk, [(r.uniform(1300, 1600), 1.0, 0.006), (r.uniform(2500, 2900), 0.5, 0.003)], r, 0.0)
        c = c + 0.4 * noise(r, len(tk), 800, 4000) * np.exp(-tk / 0.002)
        cplace(rollers, j * dur(name) / 10 + r.uniform(-0.004, 0.004), c, r.uniform(0.5, 1.0))
    hiss = cnoise(r, n, 900, 5000)
    x = motor + 0.08 * whine + 0.45 * unit(rollers) + 0.18 * hiss
    save_loop(name, x)

    # wind zones and updrafts: steady moving air with gusts, a swirling band and a whistle
    name = "wind_loop"
    r = rng(name)
    n = ns(dur(name))
    base = unit(tilt(cnoise(r, n, 90, 6000, 1), -2.5, circular=True)) * (0.7 + 0.3 * crand(r, n, 5))
    swirl = unit(csvf(r.standard_normal(n), 700 * 2.0 ** (1.2 * crand(r, n, 3)), 3.0)) * (0.6 + 0.4 * crand(r, n, 4))
    whistle = unit(csvf(r.standard_normal(n), 1600 * (1 + 0.1 * crand(r, n, 2)), 18.0))
    low = cnoise(r, n, 30, 140) * (0.6 + 0.4 * crand(r, n, 12))
    save_loop(name, base + 0.6 * swirl + 0.08 * whistle + 0.5 * low)

    # moving platforms: a soft hover hum from the thruster pods
    name = "motor_hum"
    r = rng(name)
    n = ns(dur(name))
    t = np.arange(n) / SR
    f0 = cyc(82, n)
    x = np.sin(TAU * f0 * t) + 0.35 * np.sin(TAU * 2 * f0 * t) + 0.12 * np.sin(TAU * 3 * f0 * t)
    x += 0.5 * np.sin(TAU * cyc(83, n) * t)
    x *= 0.85 + 0.15 * clfo(n, 4)
    x = unit(x) + 0.35 * cnoise(r, n, 250, 1600) * (0.7 + 0.3 * crand(r, n, 6))
    save_loop(name, x)

    # warp portal: a swirling vortex that accelerates, glittering shimmer, the exit's whump
    name = "warp_whoosh"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    rate = 3.0 + 16.0 * np.clip(t / 0.5, 0, 1) ** 1.5
    swirl_ph = TAU * np.cumsum(rate) / SR
    fc = glide(450, 4500, t, 0.5) * (1.0 + 0.45 * np.sin(swirl_ph))
    sw = unit(svf(r.standard_normal(n), fc, 4.0))
    sw *= np.minimum(t / 0.4, 1.0) ** 1.5 * np.exp(-np.maximum(t - 0.5, 0) / 0.12)
    shim = np.zeros(n)
    for j, m in enumerate((69, 76, 81, 88, 93)):
        f = ga.mtof(m) * glide(1.0, 2.0, t, 0.5) * (1.0 + 0.004 * (j - 2))
        shim += tone(f) * (0.6 + 0.4 * np.sin(TAU * (9 + j) * t))
    shim = unit(shim) * np.minimum(t / 0.45, 1.0) ** 2 * np.exp(-np.maximum(t - 0.5, 0) / 0.15)
    x = 0.8 * sw + 0.3 * shim
    place(x, 0.46, thud(tv(0.4), 95, 38, 0.1, 0.12, harm=(0.3,)), 0.9)
    place(x, 0.46, click(r, 0.1, 800, 8000, 0.005), 0.4)
    penta = (93, 95, 97, 100, 102, 105)
    for _ in range(16):
        tt = tv(0.2)
        place(x, r.uniform(0.45, 0.8), tone(ga.mtof(penta[int(r.integers(0, 6))]), tt) * env(tt, 0.002, 0.05),
              r.uniform(0.04, 0.1))
    save(name, x, fin=0.005, fout=0.15)

    name = "warp_hum"
    r = rng(name)
    n = ns(dur(name))
    t = np.arange(n) / SR
    drone = sum(a * np.sin(TAU * cyc(f, n) * t + r.uniform(0, TAU)) for f, a in
                ((55, 1.0), (110, 0.6), (110.5, 0.4), (165, 0.25), (220.5, 0.15)))
    drone *= 0.8 + 0.2 * clfo(n, 3)
    phase_band = unit(csvf(r.standard_normal(n), 1000 * 2.0 ** (0.9 * clfo(n, 1)), 5.0))
    shim = np.sin(TAU * cyc(880, n) * t) + np.sin(TAU * cyc(880.5, n) * t) + 0.6 * np.sin(TAU * cyc(1320, n) * t)
    x = unit(drone) + 0.3 * phase_band + 0.06 * shim
    save_loop(name, x)

    # a loose ball hitting the floor: a rubbery bonk with a hollow ring
    for i in range(1, 4):
        name = "prop_bonk_%d" % i
        r = rng(name)
        t = tv(dur(name))
        x = thud(t, r.uniform(160, 190), 105, 0.03, 0.03, harm=(0.25,))
        x += 0.5 * modes(t, [(r.uniform(330, 420), 1.0, 0.045), (r.uniform(780, 900), 0.4, 0.02)], r, 0.0)
        x += 0.5 * click(r, 0.3, 1000, 4500, 0.002) + 0.3 * noise(r, len(t), 200, 1200) * env(t, 0.002, 0.01)
        save(name, x, fin=0.0008, fout=0.08)

    # a collapsed platform grows back: a soft rising shimmer settling with a stony tap
    name = "platform_reform"
    r = rng(name)
    t = tv(dur(name))
    sh = unit(svf(r.standard_normal(len(t)), glide(900, 5000, t, 0.2), 4.0)) * env(t, 0.12, 0.05)
    tone_up = tone(glide(520, 1040, t, 0.2)) * env(t, 0.1, 0.08)
    x = 0.5 * sh + 0.25 * tone_up
    place(x, 0.2, thud(tv(0.2), 170, 95, 0.03, 0.025) + 0.4 * click(r, 0.2, 800, 5000, 0.002), 0.7)
    save(name, x, fin=0.01, fout=0.06)


# ===========================================================================
# map machines
# ===========================================================================
def gen_foundry():
    name = "ladle_tip"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    imp = np.zeros(n)
    pos = 0.0
    while pos < dur(name) - 0.1:
        imp[min(int(pos * SR), n - 1)] = r.uniform(0.4, 1.0)
        pos += 1.0 / (22.0 + 30.0 * np.sin(np.pi * pos / 0.7)) * r.uniform(0.85, 1.15)
    groan = fconv(imp, modes(tv(0.06), [(140, 1.0, 0.02), (330, 0.7, 0.012), (720, 0.4, 0.007)]))[:n]
    x = unit(groan) + 0.5 * noise(r, n, 40, 220) * np.sin(np.pi * np.clip(t / dur(name), 0, 1))
    for t0 in (0.05, 0.3 + r.uniform(0, 0.1), 0.55 + r.uniform(0, 0.1)):
        place(x, t0, modes(tv(0.2), bar_modes(r.uniform(850, 1000), 0.06), r, 0.02, hard=5000), 0.3)
    save(name, x, fin=0.01, fout=0.1)

    name = "ladle_pour"
    r = rng(name)
    n = ns(dur(name))
    roar = unit(tilt(cnoise(r, n, 55, 1400, 2), -3.0, circular=True)) * (0.65 + 0.35 * crand(r, n, 40, 0.4))
    glugs = np.zeros(n)
    for _ in range(26):
        cplace(glugs, r.uniform(0, dur(name)), bubble(r.uniform(70, 190), 0.12, r.uniform(0.02, 0.04), 0.4),
               r.uniform(0.3, 1.0))
    sizzle = np.zeros(n)
    grains(r, sizzle, 520, 0.0, dur(name), 3000, 11000, 0.0006, 0.002, 1.0, wrap=True)
    pops = np.zeros(n)
    grains(r, pops, 40, 0.0, dur(name), 700, 2500, 0.003, 0.008, 1.0, wrap=True)
    x = roar + 0.5 * unit(glugs) + 0.35 * unit(sizzle) + 0.3 * unit(pops)
    save_loop(name, x)

    name = "ladle_splash"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = noise(r, n, 40, 600) * env(t, 0.008, 0.15) + 0.9 * thud(t, 90, 40, 0.1, 0.12)
    s = np.zeros(n)
    grains(r, s, 160, 0.0, 0.5, 2500, 11000, 0.0006, 0.002, 1.0, decay=0.2)
    grains(r, s, 25, 0.02, 0.4, 600, 2200, 0.003, 0.008, 1.0, decay=0.15)
    x += 0.5 * unit(s)
    save(name, x, fin=0.002, fout=0.15)

    name = "ladle_hiss"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = noise(r, n, 1500, 9000) * env(t, 0.03, 0.35) * (0.8 + 0.2 * np.sin(TAU * 7 * t))
    c = np.zeros(n)
    grains(r, c, 120, 0.0, 0.9, 2500, 10000, 0.0006, 0.002, 1.0, decay=0.3)
    save(name, x + 0.3 * unit(c), fin=0.01, fout=0.3)


def gen_reef():
    for i in range(1, 3):
        name = "jelly_bounce_%d" % i
        r = rng(name)
        t = tv(dur(name))
        n = len(t)
        f = glide(r.uniform(150, 175), r.uniform(480, 560), t, 0.14) * \
            (1.0 + 0.07 * np.exp(-t / 0.15) * np.sin(TAU * 9 * t))
        bloop = (tone(f) + 0.3 * tone(2 * f) * np.exp(-t / 0.05)) * env(t, 0.006, 0.12)
        squish = noise(r, n, 100, 900) * env(t, 0.003, 0.03)
        x = bloop + 0.6 * squish
        for _ in range(9):
            place(x, r.uniform(0.02, 0.28), bubble(r.uniform(600, 1800), 0.06, r.uniform(0.008, 0.02)),
                  r.uniform(0.1, 0.3))
        save(name, band(x, None, 4200, 3), fin=0.002, fout=0.12)

    name = "vent_rumble"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = noise(r, n, 25, 170) * np.minimum(t / 0.6, 1.0) ** 1.5
    for _ in range(14):
        place(x, r.uniform(0.1, 0.72), bubble(r.uniform(150, 420), 0.08, r.uniform(0.015, 0.03)), r.uniform(0.2, 0.5))
    grains(r, x, 20, 0.2, 0.75, 500, 2000, 0.002, 0.006, 0.15)
    save(name, band(x, None, 3500, 3), fin=0.02, fout=0.08)

    name = "vent_burst"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = noise(r, n, 40, 500) * env(t, 0.01, 0.2) + 0.8 * thud(t, 85, 40, 0.1, 0.12)
    b = np.zeros(n)
    for _ in range(70):
        t0 = r.uniform(0.02, 0.75)
        place(b, t0, bubble(r.uniform(300, 2000), 0.06, r.uniform(0.006, 0.02)), r.uniform(0.2, 1.0) * np.exp(-t0 / 0.35))
    x += 0.6 * unit(b)
    save(name, band(x, None, 4500, 3), fin=0.003, fout=0.2)

    name = "vent_loop"
    r = rng(name)
    n = ns(dur(name))
    roar = cnoise(r, n, 30, 320) * (0.7 + 0.3 * crand(r, n, 8))
    hiss = cnoise(r, n, 500, 2500) * (0.6 + 0.4 * crand(r, n, 20))
    b = np.zeros(n)
    for _ in range(180):
        cplace(b, r.uniform(0, dur(name)), bubble(r.uniform(200, 1500), 0.06, r.uniform(0.006, 0.025)), r.uniform(0.2, 1.0))
    x = roar + 0.3 * hiss + 0.55 * unit(b)
    save_loop(name, cband(x, None, 4000, 3))

    name = "surge_loop"
    r = rng(name)
    n = ns(dur(name))
    rush = cnoise(r, n, 60, 900) * (0.75 + 0.25 * clfo(n, 3))
    swirl = unit(csvf(r.standard_normal(n), 380 * 2.0 ** (0.8 * crand(r, n, 4)), 2.5))
    b = np.zeros(n)
    for _ in range(30):
        cplace(b, r.uniform(0, dur(name)), bubble(r.uniform(350, 1300), 0.06, r.uniform(0.008, 0.02)), r.uniform(0.2, 1.0))
    x = rush + 0.6 * swirl + 0.25 * unit(b)
    save_loop(name, cband(x, None, 2800, 3))


def gen_orbital():
    name = "thruster_ignite"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = np.zeros(n)
    for t0 in (0.0, 0.03):
        place(x, t0, click(r, 0.02, 2000, 10000, 0.0015), 0.7)
    lit = np.maximum(t - 0.03, 0)
    wh = unit(tilt(noise(r, n, 45, 7000, 1), -2.0)) * np.minimum(lit / 0.02, 1.0) * (0.6 + 0.4 * np.exp(-lit / 0.08))
    x += wh + 0.9 * thud(t, 80, 38, 0.1, 0.12) + 0.4 * crackle(r, 0.5, 60, 1000, 6000, n=len(t))
    save(name, x, fin=0.0008, fout=0.15)

    name = "thruster_burn"
    r = rng(name)
    n = ns(dur(name))
    roar = unit(tilt(cnoise(r, n, 35, 9000, 1), -2.2, circular=True))
    formant = cnoise(r, n, 380, 950)
    rumble = cnoise(r, n, 28, 110) * (0.6 + 0.4 * crand(r, n, 30, 0.3))
    tear = 0.75 + 0.25 * crand(r, n, 45, 0.2)
    crk = crackle(r, dur(name), 300, 1000, 6000, wrap=True, n=n)
    x = roar * tear + 0.4 * formant + 0.6 * rumble + 0.5 * unit(crk)
    save_loop(name, x)

    for i in range(1, 4):
        name = "thruster_cough_%d" % i
        r = rng(name)
        t = tv(dur(name))
        x = noise(r, len(t), 100, 3000) * env(t, 0.002, 0.015) + 0.8 * thud(t, 95, 48, 0.03, 0.02)
        x += 0.4 * crackle(r, 0.06, 10, 1500, 7000, n=len(t))
        save(name, x, fin=0.0008, fout=0.04)

    name = "thruster_cutoff"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    tail = unit(svf(r.standard_normal(n), glide(6000, 250, t, 0.35), 0.8)) * env(t, 0.002, 0.15)
    x = tail + 0.4 * noise(r, n, 2500, 9000) * env(t, 0.03, 0.12) + 0.5 * thud(t, 70, 40, 0.08, 0.1)
    save(name, x, fin=0.002, fout=0.15)

    # flare: a klaxon beep in time with the gate's strobe, the launch, and the plasma wall itself
    name = "flare_alarm"
    t = tv(dur(name))
    f = 1150.0 * (1.0 + 0.02 * np.sin(TAU * 30 * t))
    x = sum(tone(f * k) / k for k in (1, 3, 5, 7)) + 0.4 * tone(f * 1.26)
    x *= np.minimum(t / 0.004, 1.0) * np.clip((0.14 - t) / 0.03, 0, 1)
    save(name, x, fin=0.001, fout=0.02)

    name = "flare_launch"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    rise = unit(svf(r.standard_normal(n), glide(200, 3200, t, 0.5), 1.2)) * np.minimum(t / 0.1, 1.0) * \
        np.exp(-np.maximum(t - 0.4, 0) / 0.35)
    x = rise + 1.0 * thud(t, 55, 28, 0.2, 0.3, harm=(0.4, 0.2)) + 0.45 * crackle(r, 0.8, 120, 1500, 9000, n=len(t))
    x += 0.35 * noise(r, n, 30, 120) * env(t, 0.05, 0.4)
    save(name, x, fin=0.002, fout=0.3)

    name = "flare_roar"
    r = rng(name)
    n = ns(dur(name))
    roar = unit(tilt(cnoise(r, n, 120, 11000, 1), -1.5, circular=True)) * (0.7 + 0.3 * crand(r, n, 60, 0.2))
    sizzle = cnoise(r, n, 6000, 12000) * (0.5 + 0.5 * crand(r, n, 80, 0.2)) ** 2
    rumble = cnoise(r, n, 35, 130) * (0.7 + 0.3 * crand(r, n, 10))
    crk = crackle(r, dur(name), 500, 1500, 9000, wrap=True, n=n)
    save_loop(name, roar + 0.35 * sizzle + 0.7 * rumble + 0.45 * unit(crk))

    # low-g bay: a floating field drone with a slow wub and a pale shimmer on top
    name = "gravity_hum"
    r = rng(name)
    n = ns(dur(name))
    t = np.arange(n) / SR
    drone = sum(a * np.sin(TAU * cyc(f, n) * t + r.uniform(0, TAU)) for f, a in
                ((55, 1.0), (55.5, 0.7), (82.5, 0.5), (110.5, 0.35), (165, 0.15)))
    wub = 0.7 + 0.3 * clfo(n, 3)
    shim = np.sin(TAU * cyc(1320, n) * t) + np.sin(TAU * cyc(1320.5, n) * t) + 0.7 * np.sin(TAU * cyc(1980, n) * t)
    air = unit(csvf(r.standard_normal(n), 600 * 2.0 ** (0.6 * clfo(n, 1, 1.0)), 6.0))
    save_loop(name, unit(drone) * wub + 0.05 * shim * (0.6 + 0.4 * clfo(n, 2)) + 0.15 * air)

    for name, up in (("gravity_on", True), ("gravity_off", False)):
        r = rng(name)
        t = tv(dur(name))
        n = len(t)
        k = np.clip(t / 0.45, 0, 1)
        ratio = (0.35 + 0.65 * k ** 0.7) if up else (1.0 - 0.7 * k ** 0.7)
        wub_rate = (3.0 + 5.0 * k) if up else (8.0 - 5.5 * k)
        wub = 0.6 + 0.4 * np.sin(TAU * np.cumsum(wub_rate) / SR)
        x = np.zeros(n)
        for f, a in ((55, 1.0), (82.5, 0.5), (110.5, 0.35), (220, 0.2), (1320, 0.05)):
            x += a * tone(f * ratio)
        shape = np.minimum(t / 0.3, 1.0) if up else np.exp(-t / 0.22)
        x = x * wub * shape * np.clip((0.6 - t) / 0.12, 0, 1)
        fc = glide(400, 2400, t, 0.4) if up else glide(2400, 300, t, 0.4)
        x += 0.3 * unit(svf(r.standard_normal(n), fc, 4.0)) * np.sin(np.pi * np.clip(t / 0.5, 0, 1))
        save(name, x, fin=0.004, fout=0.1)


def gen_clockwork():
    # an escapement tick / tock: the brass pawl, the pallet's heavy clunk, the train's ratchet,
    # and a brief whirr of gears while the pallet snaps
    for name, f_pawl, f_thud in (("escape_tick", 1900.0, 150.0), ("escape_tock", 1400.0, 105.0)):
        r = rng(name)
        t = tv(dur(name))
        n = len(t)
        x = 0.5 * modes(t, bar_modes(f_pawl, 0.045), r, 0.01, hard=9000) + 0.6 * click(r, 0.35, 2000, 9000, 0.0015)
        x += 1.0 * thud(t, f_thud, f_thud * 0.55, 0.05, 0.06)
        x += 0.5 * modes(t, [(f_thud * 2.2, 1.0, 0.03), (f_thud * 4.1, 0.6, 0.02), (f_thud * 7.3, 0.35, 0.012)], r, 0.02)
        for tj in (0.022, 0.041, 0.057):
            place(x, tj + r.uniform(-0.003, 0.003), modes(tv(0.03), bar_modes(f_pawl * 1.6, 0.008), r, 0.03), 0.15)
        whirr = np.zeros(n)
        tt = 0.01
        while tt < 0.3:
            place(whirr, tt, click(r, 0.01, 1500, 6000, 0.0008), r.uniform(0.5, 1.0))
            tt += 1.0 / 70.0
        x += 0.2 * whirr * np.exp(-t / 0.12)
        x = space(r, x, 0.9, 0.15, 200, 6000)
        save(name, x, fin=0.0008, fout=0.1)


def gen_balance():
    # scanner carriage servo: a whine with its gear hum, the rail's rumble and wheel clicks
    name = "scanner_servo"
    r = rng(name)
    n = ns(dur(name))
    t = np.arange(n) / SR
    f = cyc(420, n)
    whine = np.sin(TAU * f * t) + 0.5 * np.sin(TAU * 2 * f * t) + 0.2 * np.sin(TAU * 3 * f * t)
    gear = hum_stack(n, cyc(70, n), 10, 1.0, 1.0, r)
    rail = cnoise(r, n, 80, 600)
    clicks = np.zeros(n)
    for j in range(8):
        cplace(clicks, j * dur(name) / 8 + r.uniform(-0.005, 0.005), click(r, 0.02, 1200, 5000, 0.001), r.uniform(0.6, 1.0))
    save_loop(name, 0.4 * unit(whine) + 0.5 * gear + 0.5 * rail + 0.4 * unit(clicks))

    # crane trolley: motor whine and gear buzz, a rattling cable and chain, wheels rumbling
    name = "trolley_run"
    r = rng(name)
    n = ns(dur(name))
    t = np.arange(n) / SR
    f = cyc(300, n)
    whine = (np.sin(TAU * f * t) + 0.5 * np.sin(TAU * 2 * f * t) + 0.2 * np.sin(TAU * 4 * f * t)) * \
        (0.8 + 0.2 * np.sin(TAU * cyc(45, n) * t))
    chain = np.zeros(n)
    for _ in range(50):
        tk = tv(0.04)
        link = modes(tk, [(r.uniform(1800, 3800), 1.0, 0.01), (r.uniform(4500, 6500), 0.4, 0.005)], r, 0.0)
        cplace(chain, r.uniform(0, dur(name)), link, r.uniform(0.2, 1.0))
    rumble = cnoise(r, n, 50, 400) * (0.8 + 0.2 * crand(r, n, 18))
    save_loop(name, 0.35 * unit(whine) + 0.45 * unit(chain) + 0.7 * rumble)

    name = "trolley_clunk"
    r = rng(name)
    t = tv(dur(name))
    x = 0.5 * modes(t, plate_modes(180, 1.5, 0.15, 8, 0.6, r), r, 0.02, hard=3500) + 0.9 * thud(t, 110, 55, 0.05, 0.07)
    x += 0.7 * click(r, 0.6, 900, 6000, 0.002)
    for _ in range(7):
        place(x, r.uniform(0.02, 0.3), modes(tv(0.12), [(r.uniform(2000, 4500), 1.0, 0.03)], r, 0.0), r.uniform(0.05, 0.15))
    save(name, space(r, x, 0.8, 0.2), fin=0.0008, fout=0.12)

    # counterweight: chain links over the pulley, a faint wheel squeal, the frame's rumble
    name = "pulley_rattle"
    r = rng(name)
    n = ns(dur(name))
    links = np.zeros(n)
    for j in range(14):
        tk = tv(0.04)
        g = 1.0 if j % 2 == 0 else 0.55
        link = modes(tk, [(r.uniform(1600, 2400), 1.0, 0.012), (r.uniform(3200, 4200), 0.5, 0.006)], r, 0.0)
        cplace(links, j * dur(name) / 14 + r.uniform(-0.003, 0.003), link + 0.3 * click(r, 0.04, 800, 5000, 0.001), g)
    squeal = unit(csvf(r.standard_normal(n), cyc(1900, n) * (1 + 0.02 * crand(r, n, 3)), 30.0))
    rumble = cnoise(r, n, 60, 350)
    save_loop(name, unit(links) + 0.05 * squeal + 0.4 * rumble)

    name = "counterweight_thud"
    r = rng(name)
    t = tv(dur(name))
    x = 1.0 * thud(t, 95, 45, 0.08, 0.1) + 0.4 * modes(t, plate_modes(160, 1.2, 0.18, 8, 0.6, r), r, 0.02, hard=3000)
    x += 0.6 * click(r, 0.7, 700, 5000, 0.003)
    for _ in range(9):
        place(x, r.uniform(0.03, 0.35), modes(tv(0.1), [(r.uniform(1600, 3500), 1.0, 0.02)], r, 0.0), r.uniform(0.05, 0.18))
    save(name, space(r, x, 0.9, 0.2), fin=0.0008, fout=0.15)


def gen_gardens():
    # the trimmer: a buzzing laser-shear motor, the blades chattering, leaves being shredded
    name = "trimmer_buzz"
    r = rng(name)
    n = ns(dur(name))
    t = np.arange(n) / SR
    f0 = cyc(95, n)
    saw = buzz_wave(f0, n, 40, 1.0)
    chatter = 0.6 + 0.4 * (0.5 + 0.5 * np.sin(TAU * cyc(24, n) * t)) ** 2
    laser = cnoise(r, n, 3000, 9000) * (0.5 + 0.5 * np.sin(TAU * f0 * t)) ** 8
    leaves = np.zeros(n)
    grains(r, leaves, 260, 0.0, dur(name), 1500, 6500, 0.001, 0.004, 1.0, wrap=True)
    x = cband(saw, 60, 5000) * chatter + 0.35 * unit(laser) + 0.4 * unit(leaves)
    save_loop(name, x)


def gen_ascent():
    # the billboard: a neon transformer buzz with a high whine and irregular crackle
    name = "billboard_buzz"
    r = rng(name)
    n = ns(dur(name))
    t = np.arange(n) / SR
    f0 = cyc(120, n)
    b = cband(buzz_wave(f0, n, 30, 0.9, 0.3), 150, 4000)
    whine = np.sin(TAU * cyc(7800, n) * t)
    x = unit(b) * (0.85 + 0.15 * crand(r, n, 25, 0.3)) + 0.03 * whine + \
        0.35 * crackle(r, dur(name), 45, 2500, 9000, True, n)
    save_loop(name, x)

    def zap(r, dur, f0=120.0):
        tz = tv(dur)
        z = buzz_wave(f0, len(tz), 30, 0.9, 0.3) * np.minimum(tz / 0.002, 1) * np.clip((dur - tz) / 0.004, 0, 1)
        return z + 0.5 * noise(r, len(tz), 2500, 9000) * np.exp(-tz / 0.004)

    name = "billboard_on"
    r = rng(name)
    x = np.zeros(ns(0.45))
    for t0, d in ((0.0, 0.015), (0.05, 0.02), (0.09, 0.03), (0.16, 0.05)):
        place(x, t0, zap(r, d), 0.8)
    tt = tv(0.24)
    place(x, 0.21, buzz_wave(120, len(tt), 30, 0.9, 0.3) * env(tt, 0.003, 0.1) + 0.8 * thud(tt, 140, 80, 0.03, 0.03), 0.9)
    save(name, x, fin=0.0008, fout=0.08)

    name = "billboard_off"
    r = rng(name)
    t = tv(dur(name))
    f = glide(2200, 90, t, 0.22)
    x = 0.7 * (tone(f) + 0.3 * tone(2 * f)) * env(t, 0.002, 0.08) + 0.5 * crackle(r, 0.15, 20, n=len(t))
    place(x, 0.0, zap(r, 0.04), 0.8)
    place(x, 0.0, click(r, 0.05, 500, 6000, 0.003), 0.6)
    save(name, x, fin=0.0008, fout=0.08)

    for i in range(1, 4):
        name = "billboard_glitch_%d" % i
        r = rng(name)
        t = tv(dur(name))
        n = len(t)
        hold = int(r.uniform(0.005, 0.01) * SR)
        steps = np.repeat(r.uniform(200, 3500, n // hold + 1), hold)[:n]
        g = band(np.sign(np.sin(TAU * np.cumsum(steps) / SR)) * 0.5, None, 8000)
        crush = np.round(noise(r, n, 500, 8000) * 4) / 4
        x = (0.6 * g + 0.4 * crush) * np.minimum(t / 0.002, 1) * np.clip((0.11 - t) / 0.03, 0, 1)
        save(name, x, fin=0.0008, fout=0.02)

    # data stream: a packet spawns with a chirp of bleeps; one zipping past
    penta = (84, 86, 88, 91, 93, 96, 98, 100)
    for i in range(1, 5):
        name = "data_chirp_%d" % i
        r = rng(name)
        x = np.zeros(ns(0.16))
        start = int(r.integers(0, 4))
        direction = 1 if i % 2 else -1
        for j in range(int(r.integers(3, 5))):
            m = penta[(start + direction * j * int(r.integers(1, 3))) % len(penta)]
            tt = tv(0.05)
            f = ga.mtof(m)
            b = (tone(f, tt) + 0.25 * tone(3 * f, tt) + 0.12 * tone(5 * f, tt)) * env(tt, 0.001, 0.012)
            place(x, j * r.uniform(0.018, 0.026), b, 0.6)
        save(name, x, fin=0.0005, fout=0.03)
    for i in range(1, 3):
        name = "data_zip_%d" % i
        r = rng(name)
        t = tv(dur(name))
        f = glide(r.uniform(2600, 3200), r.uniform(500, 700), t, 0.18)
        z = (tone(f) + 0.3 * tone(2 * f)) * np.exp(-0.5 * ((t - 0.07) / 0.04) ** 2)
        w = whoosh(r, 0.25, 1500, 6000, 1200, 0.07, 0.03, 2.0)
        save(name, 0.5 * z + 0.6 * w, fin=0.002, fout=0.06)


def gen_xeno():
    # spore cap: a thick fleshy membrane struck from below by the landing - a low "bwomp" whose
    # pitch rises as the cap tautens (circular-membrane overtones, a decaying wobble as it rings),
    # a wet slap and squelch of contact, and the cap puffing out spores (a breath and a glitter)
    for i in range(1, 4):
        name = "spore_boing_%d" % i
        r = rng(name)
        t = tv(dur(name))
        n = len(t)
        f0 = r.uniform(95, 120)
        f = glide(f0, f0 * r.uniform(2.1, 2.5), t, 0.16) * \
            (1.0 + 0.06 * np.exp(-t / 0.18) * np.sin(TAU * r.uniform(9, 12) * t))
        ph = TAU * np.cumsum(f) / SR
        memb = np.zeros(n)
        for ratio, a, tau in ((1.0, 1.0, 0.14), (1.594, 0.35, 0.07), (2.136, 0.2, 0.05), (2.653, 0.1, 0.035)):
            memb += a * np.sin(ratio * ph) * np.exp(-t / tau)
        memb *= np.minimum(t / 0.004, 1.0)
        slap = noise(r, n, 150, 1500) * env(t, 0.001, 0.012)
        squelch = unit(svf(r.standard_normal(n), glide(400, 1400, t, 0.08), 3.0)) * env(t, 0.006, 0.04)
        puff = unit(svf(r.standard_normal(n), glide(2200, 900, t, 0.3), 1.2)) * env(t, 0.04, 0.12)
        sparkle = np.zeros(n)
        grains(r, sparkle, 60, 0.05, 0.5, 4000, 11000, 0.0008, 0.003, 1.0, decay=0.15)
        x = memb + 0.5 * slap + 0.3 * squelch + 0.35 * puff + 0.12 * unit(sparkle)
        save(name, x, fin=0.001, fout=0.12)

    # snapjaw: the lobes swing shut (a short swish of air pushed out between them), meet in a wet,
    # fleshy clap, the rows of chitin teeth rattle as they interlock, and the fibrous hinge creaks
    for i in range(1, 3):
        name = "snapjaw_snap_%d" % i
        r = rng(name)
        t = tv(dur(name))
        x = 0.55 * whoosh(r, dur(name), 300, r.uniform(2300, 2900), 900, 0.07, 0.03, 1.4)
        t0 = 0.075
        tt = tv(dur(name) - t0)
        m = len(tt)
        clap = thud(tt, r.uniform(150, 175), 70, 0.04, 0.05, harm=(0.4, 0.15))
        wet = noise(r, m, 250, 3000) * env(tt, 0.0008, 0.018)
        sq = unit(svf(r.standard_normal(m), glide(1600, 350, tt, 0.1), 2.5)) * env(tt, 0.004, 0.05)
        teeth = np.zeros(m)
        tj = 0.0
        for j in range(int(r.integers(7, 11))):
            ping = modes(tv(0.04), [(r.uniform(1800, 3200), 1.0, 0.008), (r.uniform(4200, 6000), 0.5, 0.004)], r, 0.0)
            place(teeth, tj, ping + 0.4 * click(r, 0.04, 2000, 9000, 0.0006), r.uniform(0.4, 1.0) * np.exp(-j * 0.15))
            tj += r.uniform(0.004, 0.009)
        place(x, t0, clap + 0.7 * wet + 0.35 * sq + 0.35 * unit(teeth))
        hinge = creak(r, 0.3, lambda u: 30.0 + 25.0 * (1.0 - u),
                      [(r.uniform(160, 190), 1.0, 0.02), (r.uniform(380, 440), 0.6, 0.012), (850, 0.35, 0.007)])
        place(x, t0 + 0.02, hinge * np.linspace(1.0, 0.0, len(hinge)) ** 2, 0.22)
        save(name, x, fin=0.004, fout=0.1)

    # and it peels open again: sticky sap strings snapping (dense tacky ticks, thinning out), a wet
    # stretch, the hinge groaning, a slow breath out and a drip or two
    name = "snapjaw_open"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    tack = np.zeros(n)
    grains(r, tack, 90, 0.0, 0.4, 1200, 5000, 0.0005, 0.0018, 1.0, decay=0.15)
    stretch = unit(svf(r.standard_normal(n), glide(220, 700, t, 0.4), 2.0)) * env(t, 0.05, 0.2)
    groan = creak(r, 0.55, lambda u: 18.0 + 22.0 * np.sin(np.pi * u),
                  [(140, 1.0, 0.02), (360, 0.6, 0.012), (820, 0.35, 0.007), (1500, 0.15, 0.004)])
    exhale = noise(r, n, 400, 2500) * np.sin(np.pi * np.clip(t / 0.6, 0, 1)) ** 2
    x = 0.45 * unit(tack) + 0.5 * stretch + 0.12 * exhale
    place(x, 0.04, groan * np.sin(np.pi * np.linspace(0, 1, len(groan))), 0.5)
    for _ in range(3):
        place(x, r.uniform(0.3, 0.6), bubble(r.uniform(500, 900), 0.06, r.uniform(0.008, 0.014), 0.8), 0.25)
    save(name, x, fin=0.01, fout=0.1)

    # acid geyser: pressure gurgling up under the pool, the column bursting out (a whoomph), a
    # roaring spray that dies away, the acid fizzing and sizzling, and droplets raining back
    name = "geyser_erupt"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = np.zeros(n)
    tb = 0.0
    while tb < 0.25:
        place(x, tb, bubble(r.uniform(150, 500), 0.08, r.uniform(0.012, 0.025), 0.9), r.uniform(0.3, 0.7) * (0.4 + tb / 0.25))
        tb += r.uniform(0.012, 0.04) * (1.0 - 0.6 * tb / 0.25)
    lit = np.maximum(t - 0.25, 0.0)
    on = np.minimum(lit / 0.02, 1.0) * (t > 0.25)
    place(x, 0.25, thud(tv(0.6), 100, 50, 0.1, 0.1), 0.7)
    place(x, 0.25, noise(r, ns(0.6), 60, 700) * env(tv(0.6), 0.005, 0.12), 0.7)
    spray = unit(tilt(noise(r, n, 200, 9000, 1), -1.5)) * (0.75 + 0.25 * noise(r, n, None, 25))
    x += 0.75 * spray * on * np.exp(-lit / 0.5)
    fizz = np.zeros(n)
    grains(r, fizz, 420, 0.28, 1.5, 3000, 10000, 0.0006, 0.002, 1.0, decay=0.5)
    x += 0.3 * unit(fizz)
    drops = np.zeros(n)
    for _ in range(30):
        place(drops, r.uniform(0.5, 1.45), bubble(r.uniform(700, 2000), 0.03, r.uniform(0.004, 0.01), 0.5) +
              0.5 * click(r, 0.03, 1500, 7000, 0.001), r.uniform(0.2, 1.0))
    x += 0.2 * unit(drops)
    save(name, x, fin=0.004, fout=0.25)

    # the sky leviathan's call, close by: a vast body resonating - a deep moan (a harmonic stack
    # through slowly moving formants, with a subharmonic growl), a higher song gliding over it, a
    # faint ring-modulated sheen, breath, and the open air of the chasm around it
    name = "leviathan_call"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)

    def voice(pts, t_on, d, f1, f2, top, vib, sub=0.0):
        m = ns(d)
        tt = np.arange(m) / SR
        u = tt / d
        f = np.exp(np.interp(u, [p[0] for p in pts], [np.log(p[1]) for p in pts])) * (1.0 + vib * np.sin(TAU * 3.2 * tt))
        F1 = np.interp(u, [p[0] for p in f1], [p[1] for p in f1])
        F2 = np.interp(u, [p[0] for p in f2], [p[1] for p in f2])
        ph = TAU * np.cumsum(f) / SR
        v = np.zeros(m)
        for kk in range(1, top + 1):
            fk = kk * f
            v += (reson(F1, fk, 4.0) + 0.8 * reson(F2, fk, 6.0) + 0.03) / kk ** 0.4 * np.sin(kk * ph) * (fk < 9000)
        v = unit(v)
        if sub:
            v += sub * np.sin(0.5 * ph) * reson(F1, 0.5 * f, 1.5)
        v *= np.sin(np.pi * np.clip(u / 0.25, 0, 1) / 2) ** 2 * np.clip((1.0 - u) / 0.35, 0, 1) ** 1.5
        out = np.zeros(n)
        place(out, t_on, v)
        return out

    moan = voice([(0, 66), (0.35, 84), (0.75, 76), (1, 58)], 0.02, 3.0, [(0, 260), (0.5, 520), (1, 320)],
                 [(0, 750), (0.5, 1200), (1, 700)], 24, 0.012, sub=0.35)
    moan = 0.9 * moan + 0.1 * moan * np.sin(TAU * 23.0 * t)
    song = voice([(0, 330), (0.5, 560), (1, 410)], 0.9, 1.8, [(0, 800), (1, 950)], [(0, 2100), (1, 1700)], 10, 0.02)
    breath = noise(r, n, 150, 1200) * np.sin(np.pi * np.clip(t / 3.2, 0, 1)) ** 2
    x = moan + 0.35 * song + 0.05 * breath
    x = space(r, x, 2.2, 0.45, 100, 5000, 0.5, 0.03)
    save(name, band(x, 40, 7000, 2), fin=0.01, fout=0.4)

    # the drift-stone monolith: a stony, inharmonic drone that throbs once a second, glassy
    # partials beating and glowing between the throbs, air swirling round the floating stones and
    # the odd grain of grit ticking off them
    name = "drift_hum"
    r = rng(name)
    n = ns(dur(name))
    t = np.arange(n) / SR
    drone = sum(a * np.sin(TAU * cyc(82.0 * q, n) * t + r.uniform(0, TAU)) for q, a in
                ((1.0, 0.6), (1.51, 0.55), (2.27, 0.35), (3.18, 0.2), (4.4, 0.1)))
    throb = 0.6 + 0.4 * (0.5 + 0.5 * clfo(n, 2)) ** 2
    glass = (np.sin(TAU * cyc(1244, n) * t) + np.sin(TAU * cyc(1246.5, n) * t) + 0.6 * np.sin(TAU * cyc(1871, n) * t) +
             0.4 * np.sin(TAU * cyc(2489, n) * t)) * (0.5 + 0.5 * clfo(n, 2, np.pi))
    swirl = unit(csvf(r.standard_normal(n), 500 * 2.0 ** (0.8 * crand(r, n, 3)), 5.0)) * (0.6 + 0.4 * crand(r, n, 4))
    grit = crackle(r, dur(name), 12, 1500, 5000, wrap=True, n=n)
    save_loop(name, unit(drone) * throb + 0.05 * glass + 0.18 * swirl + 0.1 * unit(grit))


def gen_volcano():
    # a bomb leaves the vent: a deep "thoom", a blast of gas, the rush of the bomb going up and
    # spatter crackling, with the slope throwing it back
    name = "bomb_launch"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = 0.8 * thud(t, 85, 45, 0.15, 0.18, harm=(0.45, 0.2))
    x += 0.9 * unit(tilt(noise(r, n, 80, 6000, 1), -2.0)) * env(t, 0.004, 0.09)
    x += 0.6 * whoosh(r, dur(name), 300, 1800, 500, 0.18, 0.1, 1.3)
    x += 0.35 * unit(crackle(r, 0.7, 70, 1200, 6000, n=n)) * np.exp(-t / 0.3)
    x += 0.3 * noise(r, n, 50, 200) * env(t, 0.03, 0.3)
    save(name, space(r, x, 1.4, 0.25, 100, 4000, 0.4), fin=0.0008, fout=0.2)

    # an incoming lava bomb: a tumbling molten rock tearing through the air - a falling whistle (it
    # is coming in fast), the rush of air growing as it closes, a tumbling flutter and a fizzing
    # smoke trail; it ends at the moment of impact (bomb_impact takes over)
    name = "bomb_whistle"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    u = t / dur(name)
    grow = (0.08 + 0.92 * u ** 2) * np.clip((dur(name) - t) / 0.06, 0, 1)
    f = 1900.0 * (650.0 / 1900.0) ** (u ** 1.3)
    tumble = 0.6 + 0.4 * np.sin(TAU * np.cumsum(9.0 + 6.0 * u) / SR)
    whistle = unit(svf(r.standard_normal(n), f, 14.0))
    rush = unit(svf(r.standard_normal(n), f * 0.55, 1.2))
    fizz = np.zeros(n)
    grains(r, fizz, 300, 0.0, dur(name), 3000, 10000, 0.0006, 0.002, 1.0)
    x = (0.5 * whistle + 0.7 * rush + 0.12 * tone(f) ) * tumble * grow + 0.15 * unit(fizz) * grow
    save(name, x, fin=0.05, fout=0.05)

    # a molten bomb lands: a heavy splat (a thud and a burst of low, wet noise), the crust it hits
    # shattering (stone modes, a crack, flying chips), molten spatter and a sizzling hiss
    for i in range(1, 4):
        name = "bomb_impact_%d" % i
        r = rng(name)
        t = tv(dur(name))
        n = len(t)
        x = 0.75 * thud(t, r.uniform(95, 110), 50, 0.1, 0.12, harm=(0.4, 0.2))
        x += 1.0 * unit(svf(r.standard_normal(n), glide(900, 200, t, 0.15), 1.5)) * env(t, 0.002, 0.07)
        x += 0.6 * click(r, dur(name), 800, 9000, 0.004)
        x += 0.35 * modes(t, [(r.uniform(260, 320), 1.0, 0.03), (r.uniform(520, 640), 0.7, 0.02),
                              (r.uniform(980, 1150), 0.45, 0.012), (r.uniform(1700, 2000), 0.3, 0.007)], r, 0.0)
        chips = np.zeros(n)
        grains(r, chips, 40, 0.02, 0.5, 1000, 6000, 0.002, 0.006, 1.0, decay=0.15)
        x += 0.4 * unit(chips)
        for _ in range(int(r.integers(5, 9))):
            place(x, r.uniform(0.05, 0.4), bubble(r.uniform(200, 600), 0.1, r.uniform(0.015, 0.03), 0.4), 0.12)
        x += 0.25 * noise(r, n, 2500, 9000) * env(t, 0.03, 0.35) * (0.7 + 0.3 * noise(r, n, None, 20))
        save(name, space(r, x, 0.9, 0.2, 120, 5000), fin=0.0008, fout=0.2)

    # a flooded crater filling: thick lava churning - a low viscous roar, slow heavy bubbles bulging
    # and bursting (blorps), crust crackling as it rides up, a sizzle along the rim
    name = "lava_rise"
    r = rng(name)
    n = ns(dur(name))
    churn = unit(tilt(cnoise(r, n, 45, 900, 2), -3.0, circular=True)) * (0.7 + 0.3 * crand(r, n, 10))
    blorps = np.zeros(n)
    for j in range(9):
        g = r.uniform(0.2, 0.35)
        tt = tv(g + 0.2)
        f = r.uniform(60, 110) * (1.0 + 0.8 * np.clip(tt / g, 0, 1) ** 1.5)
        b = (tone(f) + 0.5 * tone(2 * f) + 0.25 * tone(3 * f)) * np.minimum(tt / (g * 0.7), 1.0) ** 2 * (tt < g)
        b = band(b, None, 700)
        pop = noise(r, len(tt), 200, 1500) * np.exp(-np.maximum(tt - g, 0) / 0.015) * (tt >= g)
        ring = tone(glide(300, 120, np.maximum(tt - g, 0), 0.08)) * np.exp(-np.maximum(tt - g, 0) / 0.04) * (tt >= g)
        cplace(blorps, j * dur(name) / 9 + r.uniform(0, 0.2), taper(b + 0.4 * pop + 0.3 * ring), r.uniform(0.5, 1.0))
    crk = crackle(r, dur(name), 140, 1500, 7000, wrap=True, n=n)
    sizzle = cnoise(r, n, 3000, 9000) * (0.5 + 0.5 * crand(r, n, 20)) ** 2
    save_loop(name, churn + 0.6 * unit(blorps) + 0.3 * unit(crk) + 0.15 * sizzle)

    # a basalt column settling into the lava: a clunk as it gives, stone grinding on stone (a slow
    # stick-slip through the column's dead resonances), the groan of its weight, the lava bulging
    # round it in thick bubbles, and a sizzle where the hot rock goes in
    for i in range(1, 3):
        name = "basalt_sink_%d" % i
        r = rng(name)
        t = tv(dur(name))
        n = len(t)
        x = 0.8 * thud(t, 120, 60, 0.05, 0.06) + 0.4 * click(r, dur(name), 600, 6000, 0.003)
        grind = creak(r, 1.2, lambda u: 24.0 + 26.0 * np.sin(np.pi * u) ** 0.8,
                      [(r.uniform(110, 130), 1.0, 0.03), (r.uniform(260, 300), 0.7, 0.02),
                       (r.uniform(540, 620), 0.45, 0.012), (r.uniform(1100, 1300), 0.25, 0.006)])
        win = np.sin(np.pi * np.linspace(0, 1, len(grind))) ** 0.5
        rough = noise(r, len(grind), 200, 2500) * (0.4 + 0.6 * np.abs(noise(r, len(grind), None, 30)))
        place(x, 0.04, (grind + 0.35 * rough) * win, 0.8)
        grains(r, x, 60, 0.05, 1.2, 600, 4000, 0.002, 0.006, 0.12)
        fg = glide(95, 70, t, 1.2)
        x += 0.2 * (tone(fg) + 0.5 * tone(2 * fg)) * np.sin(np.pi * np.clip(t / 1.3, 0, 1))
        for _ in range(8):
            place(x, r.uniform(0.2, 1.2), bubble(r.uniform(90, 250), 0.2, r.uniform(0.03, 0.05), 0.5), r.uniform(0.2, 0.4))
        x += 0.12 * noise(r, n, 2500, 8000) * env(t, 0.2, 0.5)
        save(name, x, fin=0.002, fout=0.25)

    # a fumarole: hot gas jetting from a vent - a broad roaring hiss peaking at 1.5-3 kHz (jet
    # noise) that surges, a low rumble in the vent's throat and sputters of grit
    name = "fumarole_loop"
    r = rng(name)
    n = ns(dur(name))
    jet = unit(tilt(cnoise(r, n, 250, 9000, 1), -1.5, circular=True))
    jet_band = unit(csvf(r.standard_normal(n), 1800 * 2.0 ** (0.35 * crand(r, n, 4)), 1.5))
    puff = 0.7 + 0.3 * crand(r, n, 6)
    throat = cnoise(r, n, 60, 300) * (0.6 + 0.4 * crand(r, n, 14))
    sputter = crackle(r, dur(name), 60, 1500, 6000, wrap=True, n=n)
    save_loop(name, (0.7 * jet + 0.6 * jet_band) * puff + 0.5 * throat + 0.25 * unit(sputter))

    # a lava fall: a thick molten curtain pouring over a ledge - a heavy, dark, slow roar (viscous,
    # darker than water), the sheet tearing, big glugs and plops where it lands, spatter and the
    # hiss of the cooling skin
    name = "lavafall_loop"
    r = rng(name)
    n = ns(dur(name))
    roar = unit(tilt(cnoise(r, n, 50, 2200, 2), -3.5, circular=True)) * (0.7 + 0.3 * crand(r, n, 24, 0.4))
    rip = cnoise(r, n, 300, 1400) * (0.5 + 0.5 * crand(r, n, 40, 0.3)) ** 2
    glugs = np.zeros(n)
    for _ in range(22):
        cplace(glugs, r.uniform(0, dur(name)), bubble(r.uniform(60, 160), 0.25, r.uniform(0.03, 0.06), 0.5),
               r.uniform(0.3, 1.0))
    plops = np.zeros(n)
    for _ in range(14):
        tt = tv(0.2)
        p = tone(glide(160, 70, tt, 0.08)) * env(tt, 0.002, 0.04) + 0.5 * noise(r, len(tt), 150, 1500) * env(tt, 0.001, 0.01)
        cplace(plops, r.uniform(0, dur(name)), taper(p), r.uniform(0.4, 1.0))
    spatter = np.zeros(n)
    grains(r, spatter, 300, 0.0, dur(name), 1500, 8000, 0.0008, 0.003, 1.0, wrap=True)
    hiss = cnoise(r, n, 3000, 9000)
    save_loop(name, roar + 0.35 * rip + 0.45 * unit(glugs) + 0.35 * unit(plops) + 0.25 * unit(spatter) + 0.1 * hiss)

    # cooled crust giving under your weight: a brittle snap exciting the plate's stony modes, a
    # crackle running away through it, a thump, a short creak and a puff of steam through the split
    for i in range(1, 3):
        name = "crust_crack_%d" % i
        r = rng(name)
        t = tv(dur(name))
        n = len(t)
        x = click(r, dur(name), 1200, 10000, 0.0015)
        x += 0.5 * modes(t, plate_modes(r.uniform(380, 460), 1.5, 0.02, 8, 0.7, r), r, 0.02, hard=5000)
        x += 0.6 * thud(t, 160, 90, 0.02, 0.02)
        tj, g = 0.01, 0.7
        for _ in range(12):
            tj += r.uniform(0.006, 0.03)
            place(x, tj, click(r, 0.02, 1500, 8000, 0.0008) +
                  0.5 * modes(tv(0.02), [(r.uniform(1500, 3500), 1.0, 0.004)], r, 0.0), g)
            g *= 0.8
        cr = creak(r, 0.25, lambda u: 40.0 - 20.0 * u, [(180, 1.0, 0.012), (420, 0.6, 0.008), (900, 0.3, 0.005)])
        place(x, 0.03, cr * np.linspace(1.0, 0.0, len(cr)), 0.25)
        x += 0.1 * noise(r, n, 2500, 8000) * env(t, 0.03, 0.15)
        save(name, x, fin=0.0008, fout=0.1)

    # the crust plate gives way: a big crack, the slab breaking into chunks (several stony plate
    # hits), crumbling debris, and the molten rock under it - a thick gloop and a burst of sizzle
    name = "crust_break"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = click(r, dur(name), 600, 10000, 0.006) + 0.7 * thud(t, 120, 62, 0.08, 0.08)
    for _ in range(5):
        tc = r.uniform(0.03, 0.25)
        chunk = modes(tv(0.25), plate_modes(r.uniform(250, 500), 1.4, 0.025, 6, 0.7, r), r, 0.02, hard=4000)
        place(x, tc, 0.5 * chunk + 0.4 * click(r, 0.25, 800, 7000, 0.002), r.uniform(0.3, 0.7))
    grains(r, x, 70, 0.05, 0.7, 500, 5000, 0.002, 0.008, 0.25, decay=0.25)
    tg = tv(0.35)
    fgl = glide(70, 150, tg, 0.18)
    gloop = (tone(fgl) + 0.5 * tone(2 * fgl)) * np.minimum(tg / 0.1, 1.0) * np.exp(-tg / 0.12)
    place(x, 0.12, taper(band(gloop, None, 900)), 0.5)
    lit = np.maximum(t - 0.12, 0.0)
    x += 0.25 * noise(r, n, 2500, 9000) * np.minimum(lit / 0.04, 1.0) * np.exp(-lit / 0.35) * (t > 0.12)
    save(name, space(r, x, 0.8, 0.15, 120, 6000), fin=0.0008, fout=0.2)

    # an eruption pulse: the mountain clears its throat - a deep blast (a heavy thud and a
    # pressure wave of dark noise), the fountain's roar surging up and dying away, dense crackle of
    # ejecta, a rumble, and the boom rolling back off the slopes
    name = "eruption_boom"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    boom = thud(t, 72, 38, 0.3, 0.4, harm=(0.5, 0.25))
    blast = unit(tilt(noise(r, n, 35, 5000, 1), -3.0)) * env(t, 0.006, 0.18)
    swell = np.minimum(t / 0.2, 1.0) * np.exp(-np.maximum(t - 0.2, 0.0) / 0.9)
    roar = unit(tilt(noise(r, n, 70, 4000, 1), -2.5)) * swell * (0.7 + 0.3 * np.abs(noise(r, n, None, 8)))
    crk = unit(crackle(r, 2.2, 400, 800, 6000, n=n)) * env(t, 0.15, 0.7)
    rumble = noise(r, n, 45, 180) * env(t, 0.05, 0.9)
    x = 0.7 * boom + 0.9 * blast + 1.0 * roar + 0.3 * crk + 0.25 * rumble
    y = x.copy()
    for dly, g in ((r.uniform(0.3, 0.45), 0.35), (r.uniform(0.75, 0.95), 0.2)):
        place(y, dly, band(boom + blast, None, 900), g)
    save(name, band(space(r, y, 1.8, 0.3, 80, 4000, 0.4), None, 7000), fin=0.001, fout=0.5)


def ice_modes(r, t, f11, tau, count=6, hard=None):
    """Ice: a hard, bright solid - glass-like plate modes, but damped faster than glass."""
    return modes(t, plate_modes(f11, 1.3, tau, count, 0.5, r), r, 0.02, hard=hard)


def pew(dur, f_hi, f_lo):
    """The 'pew' of ice under strain: ice is dispersive (flexural waves travel faster the higher
    they are), so a crack reaches the ear as a laser-like chirp sweeping down,
    f = f_hi / (1 + t / t0)^2."""
    t = tv(dur)
    t0 = dur / (np.sqrt(f_hi / f_lo) - 1.0)
    f = f_hi / (1.0 + t / t0) ** 2
    return taper((tone(f) + 0.2 * tone(2 * f)) * env(t, 0.0015, dur * 0.4))


def gen_glacier():
    # an icicle shivering loose: a fast run of tiny ticks (the ice fracturing at its root), then a
    # sharp, glassy crack, the icicle ringing (a thin ice rod) and a pew through the overhang
    name = "icicle_crack"
    r = rng(name)
    t = tv(dur(name))
    x = np.zeros(len(t))
    tj, g = 0.0, 0.25
    while tj < 0.12:
        place(x, tj, click(r, 0.01, 3000, 11000, 0.0005), g)
        tj += r.uniform(0.004, 0.02) * (1.0 - 0.6 * tj / 0.12)
        g = min(g * 1.12, 0.8)
    tt = tv(dur(name) - 0.13)
    ring = modes(tt, bar_modes(r.uniform(1400, 1800), 0.15, (1.0, 0.6, 0.4, 0.25, 0.15), 0.6), r, 0.02, hard=9000)
    place(x, 0.13, click(r, dur(name) - 0.13, 1500, 12000, 0.002) + 0.5 * ring)
    place(x, 0.135, pew(0.25, 5000, 900), 0.3)
    save(name, x, fin=0.001, fout=0.1)

    # the icicle dropping: an airy whoosh rising as it gathers speed (a band sweeping up and
    # narrowing), and a thin glassy ring from the tumbling rod
    name = "icicle_fall"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    u = t / dur(name)
    wh = unit(svf(r.standard_normal(n), glide(600, 3200, t, 0.7), 2.5)) * u ** 1.5
    ring = tone(glide(2400, 2600, t, 0.7)) * (0.6 + 0.4 * np.sin(TAU * 14.0 * t))
    save(name, wh + 0.1 * ring * u, fin=0.02, fout=0.05)

    # the icicle hits the ground and explodes: a sharp crack and a thud, dozens of glassy shards
    # (bright, short ice modes) spraying and skittering, tinkles settling
    for i in range(1, 3):
        name = "icicle_shatter_%d" % i
        r = rng(name)
        t = tv(dur(name))
        x = click(r, dur(name), 1200, 12000, 0.003) + 0.6 * thud(t, 160, 80, 0.03, 0.03)
        x += 0.4 * ice_modes(r, t, r.uniform(700, 900), 0.05, hard=8000)
        for _ in range(40):
            tj = r.gamma(1.3, 0.08)
            f = r.uniform(2500, 9000)
            shard = modes(tv(0.1), [(f, 1.0, r.uniform(0.01, 0.04)), (f * 2.76, 0.4, 0.008)], r, 0.0)
            place(x, tj, shard, r.uniform(0.1, 0.6) * np.exp(-tj / 0.25))
        grains(r, x, 60, 0.0, 0.4, 2000, 10000, 0.0006, 0.002, 0.2, decay=0.15)
        save(name, space(r, x, 0.7, 0.15, 300, 10000, 0.6), fin=0.0008, fout=0.15)

    # a blizzard gust front shoving past: the wind swelling and passing (a band rising to the pass,
    # then falling), a howl riding it, a blast of driven snow and a low buffet
    name = "gust_whoosh"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    tp = 0.55
    ge = np.where(t < tp, np.exp(-0.5 * ((t - tp) / 0.22) ** 2), np.exp(-0.5 * ((t - tp) / 0.32) ** 2))
    w = whoosh(r, dur(name), 200, 1400, 400, tp, 0.22, 1.2)
    howl = unit(svf(r.standard_normal(n), np.interp(t, [0, tp, dur(name)], [380, 900, 500]), 10.0)) * ge ** 1.3
    snow = noise(r, n, 3000, 9000) * ge ** 1.5
    low = noise(r, n, 40, 200) * ge
    save(name, w + 0.45 * howl + 0.35 * snow + 0.3 * low, fin=0.02, fout=0.2)

    # thin ice under your feet: a sharp snap, the panel's glassy plate modes, pews running out
    # through the sheet, and a creak
    for i in range(1, 3):
        name = "ice_crack_%d" % i
        r = rng(name)
        t = tv(dur(name))
        x = click(r, dur(name), 1500, 12000, 0.0015) + 0.5 * ice_modes(r, t, r.uniform(500, 650), 0.03, hard=7000)
        x += 0.4 * thud(t, 180, 100, 0.02, 0.02)
        for _ in range(int(r.integers(2, 4))):
            place(x, r.uniform(0.0, 0.08), pew(r.uniform(0.2, 0.35), r.uniform(3500, 6000), r.uniform(500, 900)),
                  r.uniform(0.2, 0.4))
        cr = creak(r, 0.2, lambda u: 60.0 - 30.0 * u, [(300, 1.0, 0.01), (700, 0.6, 0.006), (1500, 0.3, 0.004)])
        place(x, 0.05, cr * np.linspace(1.0, 0.0, len(cr)), 0.2)
        save(name, x, fin=0.0008, fout=0.12)

    # the panel gives way: a big crack and boom, the sheet breaking into slabs (ice plate hits), a
    # spray of shards, and chunks tumbling away into the crevasse (duller and fainter as they fall)
    name = "ice_break"
    r = rng(name)
    t = tv(dur(name))
    x = click(r, dur(name), 800, 12000, 0.005) + 0.7 * thud(t, 130, 62, 0.06, 0.07)
    place(x, 0.01, pew(0.4, 5000, 400), 0.3)
    for _ in range(5):
        slab = ice_modes(r, tv(0.3), r.uniform(350, 700), 0.04, 6, 6000) + 0.4 * click(r, 0.3, 800, 8000, 0.002)
        place(x, r.uniform(0.02, 0.2), slab, r.uniform(0.3, 0.7))
    for _ in range(50):
        tj = r.gamma(1.3, 0.1)
        f = r.uniform(2000, 8000)
        place(x, tj, modes(tv(0.08), [(f, 1.0, r.uniform(0.008, 0.03))], r, 0.0), r.uniform(0.05, 0.3) * np.exp(-tj / 0.3))
    for j in range(6):
        tf = 0.35 + 0.1 * j + r.uniform(0, 0.05)
        chunk = thud(tv(0.2), r.uniform(140, 200), 80, 0.03, 0.03) + 0.4 * ice_modes(r, tv(0.2), r.uniform(500, 900), 0.02)
        place(x, tf, band(chunk, None, 2500 - 300 * j), 0.35 * 0.75 ** j)
    save(name, space(r, x, 1.0, 0.25, 200, 8000, 0.5), fin=0.0008, fout=0.2)

    # the avalanche: a massive tumbling roar (dark noise churning), blocks of snow thudding inside
    # it, the hiss of the powder cloud and a rumble through the ground
    name = "avalanche_roar"
    r = rng(name)
    n = ns(dur(name))
    roar = unit(tilt(cnoise(r, n, 45, 3000, 2), -3.0, circular=True)) * (0.7 + 0.3 * crand(r, n, 30, 0.4))
    churn = cnoise(r, n, 200, 900) * (0.5 + 0.5 * crand(r, n, 20, 0.3)) ** 2
    thumps = np.zeros(n)
    for _ in range(16):
        tt = tv(0.3)
        th = thud(tt, r.uniform(90, 140), 55, 0.06, 0.06) + 0.5 * noise(r, len(tt), 100, 700) * env(tt, 0.002, 0.04)
        cplace(thumps, r.uniform(0, dur(name)), taper(th), r.uniform(0.3, 1.0))
    powder = cnoise(r, n, 2000, 8000) * (0.6 + 0.4 * crand(r, n, 12))
    rumble = cnoise(r, n, 40, 130) * (0.7 + 0.3 * crand(r, n, 8))
    save_loop(name, roar + 0.4 * churn + 0.4 * unit(thumps) + 0.2 * powder + 0.35 * rumble)

    # the avalanche letting go: the snowpack fracturing (a deep 'whumpf' and a crack across the
    # slope with a pew), then a rumble building as the slide gathers
    name = "avalanche_rumble"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = 0.8 * thud(t, 95, 48, 0.15, 0.18) + 0.6 * noise(r, n, 60, 600) * env(t, 0.01, 0.15)
    place(x, 0.05, click(r, 0.4, 600, 8000, 0.008), 0.6)
    place(x, 0.06, pew(0.5, 4000, 300), 0.25)
    grow = np.clip((t - 0.3) / 2.0, 0, 1) ** 1.5
    x += 0.9 * unit(tilt(noise(r, n, 45, 2500, 2), -3.0)) * grow * (0.7 + 0.3 * noise(r, n, None, 6))
    for j in range(10):
        tb = 0.5 + 1.9 * np.sqrt(r.uniform(0, 1))
        place(x, tb, thud(tv(0.3), r.uniform(90, 140), 55, 0.06, 0.06), 0.3 * np.clip((tb - 0.3) / 2.0, 0, 1))
    save(name, x, fin=0.002, fout=0.3)

    # a lump of snow landing: a soft, dull whump (a low pat and a burst of muffled noise), a
    # crumble of powder and a faint crunch
    for i in range(1, 4):
        name = "snow_thump_%d" % i
        r = rng(name)
        t = tv(dur(name))
        n = len(t)
        x = thud(t, r.uniform(120, 150), 62, 0.05, 0.05, harm=(0.2,)) + 0.7 * noise(r, n, 80, 700) * env(t, 0.003, 0.04)
        x += 0.25 * noise(r, n, 1500, 6000) * env(t, 0.01, 0.08)
        crunch = np.zeros(n)
        grains(r, crunch, 30, 0.0, 0.1, 500, 3000, 0.001, 0.004, 1.0, decay=0.05)
        save(name, band(x + 0.3 * unit(crunch), None, 7000), fin=0.001, fout=0.1)


def gen_desert():
    # a spike trap firing: the stone latch clunks, a rank of bronze spikes shoots up out of its
    # sleeves (a fast metallic 'shing': a bright scrape sweeping up and the spikes ringing), a thud
    # as they hit the top of their travel, and a puff of sand
    for i in range(1, 3):
        name = "spike_trap_%d" % i
        r = rng(name)
        t = tv(dur(name))
        x = 0.7 * (thud(t, 140, 80, 0.02, 0.03) + 0.5 * click(r, dur(name), 600, 5000, 0.002))
        for j in range(5):
            tj = 0.03 + j * r.uniform(0.004, 0.01)
            tt = tv(dur(name) - tj)
            m = len(tt)
            scrape = unit(svf(r.standard_normal(m), glide(2500, 7000, tt, 0.06), 4.0)) * env(tt, 0.003, 0.035)
            ring = modes(tt, bar_modes(r.uniform(1100, 1500), 0.08, (1.0, 0.6, 0.4, 0.25, 0.12), 0.6), r, 0.02, hard=9000)
            place(x, tj, 1.0 * scrape + 0.15 * ring, r.uniform(0.6, 1.0))
        place(x, 0.09, thud(tv(0.3), 180, 100, 0.02, 0.025) + 0.5 * click(r, 0.3, 1000, 7000, 0.0015), 0.6)
        puff = np.zeros(len(t))
        grains(r, puff, 40, 0.09, 0.3, 1500, 7000, 0.0008, 0.003, 1.0, decay=0.08)
        x += 0.2 * unit(puff) + 0.15 * noise(r, len(t), 1000, 6000) * env(np.maximum(t - 0.09, 0), 0.01, 0.08) * (t > 0.09)
        save(name, space(r, x, 0.9, 0.2, 200, 7000), fin=0.0008, fout=0.1)

    # the spikes sliding back down: a slower, falling bronze scrape, the plate grinding as it
    # resets, and a clunk
    name = "spike_retract"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = 0.6 * unit(svf(r.standard_normal(n), glide(4200, 1400, t, 0.35), 5.0)) * env(t, 0.02, 0.15)
    x += 0.15 * modes(t, bar_modes(r.uniform(1100, 1400), 0.1, (1.0, 0.5, 0.3, 0.15, 0.08), 0.6), r, 0.02, hard=6000)
    gr = creak(r, 0.4, lambda u: 40.0 + 20.0 * u, [(220, 1.0, 0.015), (520, 0.6, 0.01), (1100, 0.3, 0.006)])
    place(x, 0.02, gr * np.sin(np.pi * np.linspace(0, 1, len(gr))), 0.35)
    place(x, 0.45, thud(tv(0.15), 170, 90, 0.02, 0.03) + 0.5 * click(r, 0.15, 800, 6000, 0.002), 0.7)
    save(name, space(r, x, 0.9, 0.2, 200, 7000), fin=0.004, fout=0.08)

    # a curtain of sand pouring from the ceiling: a dense, dry hiss of grains, a softer pouring
    # body, the patter where it lands, and a touch of the hall
    name = "sandfall_loop"
    r = rng(name)
    n = ns(dur(name))
    hiss = cnoise(r, n, 1800, 9000) * (0.75 + 0.25 * crand(r, n, 40, 0.3))
    ticks = crackle(r, dur(name), 900, 2500, 10000, wrap=True, n=n)
    body = cnoise(r, n, 250, 1800) * (0.8 + 0.2 * crand(r, n, 12))
    pat = np.zeros(n)
    grains(r, pat, 160, 0.0, dur(name), 200, 900, 0.002, 0.006, 1.0, wrap=True)
    dry = 0.7 * hiss + 0.3 * unit(ticks) + 0.5 * body + 0.45 * unit(pat)
    wet = cconv(dry, room_ir(r, 1.2, 150, 6000))
    save_loop(name, dry + 0.25 * unit(wet) * np.max(np.abs(dry)))

    # sinking sand swallowing a foot: a low sucking pull (a band sweeping down), sand shifting and
    # pouring in round it, and a deep, dull gulp at the end
    name = "quicksand_sink"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = 0.7 * unit(svf(r.standard_normal(n), glide(700, 150, t, 0.9), 2.5)) * np.sin(np.pi * np.clip(t / 1.0, 0, 1)) ** 1.5
    x += 0.35 * noise(r, n, 800, 6000) * (0.4 + 0.6 * np.abs(noise(r, n, None, 12))) * np.sin(np.pi * t / dur(name))
    x += 0.4 * noise(r, n, 60, 300) * np.sin(np.pi * np.clip(t / 0.9, 0, 1))
    grains(r, x, 80, 0.05, 1.0, 2500, 8000, 0.0006, 0.002, 0.15)
    place(x, 0.85, thud(tv(0.3), 120, 55, 0.08, 0.06) + 0.6 * bubble(90, 0.3, 0.04, 0.8), 0.7)
    save(name, x, fin=0.02, fout=0.15)

    # a dust devil: wind swirling round (bands whose centres circle up and down, whole cycles per
    # loop), sand whipped round in pulses with the swirl, a thin whistle and a low buffet
    name = "dustdevil_loop"
    r = rng(name)
    n = ns(dur(name))
    base = unit(tilt(cnoise(r, n, 100, 6000, 1), -2.5, circular=True))
    swirl = unit(csvf(r.standard_normal(n), 900 * 2.0 ** (0.9 * clfo(n, 3)), 2.5))
    swirl2 = unit(csvf(r.standard_normal(n), 1800 * 2.0 ** (0.7 * clfo(n, 5, 1.3)), 4.0))
    sand = cnoise(r, n, 2500, 9000) * (0.5 + 0.5 * clfo(n, 3)) ** 2
    whistle = unit(csvf(r.standard_normal(n), 2200 * (1.0 + 0.1 * crand(r, n, 3)), 16.0))
    low = cnoise(r, n, 40, 160) * (0.6 + 0.4 * crand(r, n, 10))
    save_loop(name, 0.6 * base + 0.7 * swirl + 0.35 * swirl2 + 0.35 * sand + 0.06 * whistle + 0.35 * low)

    # heat haze: pale, glassy tones wavering in and out of tune (slow, deep vibrato at different
    # rates), swelling and fading like the air, over a breathy band
    name = "mirage_shimmer"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = np.zeros(n)
    for f, a in ((1318.5, 1.0), (1760.0, 0.7), (1975.5, 0.6), (2637.0, 0.45), (3520.0, 0.3)):
        rate = r.uniform(3.0, 6.0)
        x += a * tone(f * (1.0 + 0.012 * np.sin(TAU * rate * t + r.uniform(0, TAU))))
    swell = np.sin(np.pi * t / dur(name)) ** 2
    air = unit(svf(r.standard_normal(n), 2500 * (1.0 + 0.3 * np.sin(TAU * 3.0 * t)), 3.0))
    save(name, (unit(x) + 0.25 * air) * swell, fin=0.02, fout=0.1)

    # the stone ball rolling: a deep rumble, knocks from its chips and flats coming round in a
    # repeating pattern (it turns twice per loop), grit crushed under it and dust
    name = "boulder_roll"
    r = rng(name)
    n = ns(dur(name))
    rumble = cnoise(r, n, 45, 400) * (0.6 + 0.4 * crand(r, n, 16, 0.5))
    knocks = np.zeros(n)
    marks = [(r.uniform(0, 1.0), r.uniform(0.4, 1.0), r.uniform(110, 150)) for _ in range(5)]
    for rev in range(2):
        for ph, g, f in marks:
            tt = tv(0.2)
            k = thud(tt, f, 55, 0.04, 0.05) + 0.3 * band(click(r, 0.2, 400, 4000, 0.004), None, 3000)
            cplace(knocks, rev * 1.0 + ph, taper(k), g)
    grit = crackle(r, dur(name), 400, 800, 5000, wrap=True, n=n)
    crunch = np.zeros(n)
    grains(r, crunch, 200, 0.0, dur(name), 1000, 4000, 0.001, 0.004, 1.0, wrap=True)
    dust = cnoise(r, n, 1500, 5000)
    save_loop(name, unit(rumble) + 0.6 * unit(knocks) + 0.35 * unit(grit) + 0.2 * unit(crunch) + 0.12 * dust)

    # the ball smashing into a wall or dropping into its pit: a huge thud, a stone crack, rubble
    # tumbling and rattling, and a dust hiss, in the temple
    name = "boulder_impact"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = 0.9 * thud(t, 95, 55, 0.15, 0.18, harm=(0.5, 0.25)) + 0.7 * click(r, dur(name), 500, 9000, 0.008)
    x += 0.7 * noise(r, n, 60, 500) * env(t, 0.003, 0.15)
    for _ in range(30):
        tj = 0.05 + r.gamma(1.5, 0.15)
        f0 = r.uniform(300, 1500)
        rock = modes(tv(0.12), [(f0, 1.0, 0.012), (f0 * 1.71, 0.6, 0.008), (f0 * 2.63, 0.4, 0.005)], r, 0.0)
        place(x, tj, rock + 0.5 * click(r, 0.12, f0 * 0.8, min(f0 * 7, 12000), 0.002), r.uniform(0.1, 0.4) * np.exp(-tj / 0.5))
    grains(r, x, 60, 0.05, 1.0, 800, 5000, 0.002, 0.008, 0.2, decay=0.3)
    x += 0.12 * noise(r, n, 1000, 6000) * env(t, 0.05, 0.4)
    save(name, space(r, x, 1.4, 0.35, 100, 6000), fin=0.0008, fout=0.3)

    # a sandstone block sliding: stone grinding on stone (stick-slip through the block's dead
    # resonances and a rough scrape), sand crunching under it, and the block settling with a knock
    for i in range(1, 3):
        name = "stone_grind_%d" % i
        r = rng(name)
        t = tv(dur(name))
        x = np.zeros(len(t))
        grind = creak(r, 1.0, lambda u: 26.0 + 26.0 * np.sin(np.pi * u) ** 0.8,
                      [(r.uniform(100, 130), 1.0, 0.03), (r.uniform(240, 300), 0.7, 0.02),
                       (r.uniform(520, 640), 0.45, 0.012), (r.uniform(1100, 1350), 0.25, 0.006)])
        m = len(grind)
        rough = noise(r, m, 200, 2500) * (0.4 + 0.6 * np.abs(noise(r, m, None, 30)))
        place(x, 0.02, (grind + 0.4 * rough) * np.sin(np.pi * np.linspace(0, 1, m)) ** 0.5, 0.9)
        grains(r, x, 40, 0.05, 1.0, 1500, 6000, 0.001, 0.004, 0.15)
        place(x, 1.03, thud(tv(0.25), 140, 70, 0.03, 0.04) + 0.5 * click(r, 0.25, 500, 5000, 0.003), 0.6)
        save(name, space(r, x, 1.0, 0.25, 150, 6000), fin=0.004, fout=0.12)


# ===========================================================================
# the second set of new worlds: Phantom Manor (D minor), Storm Armada (E minor),
# Sugar Rush (C major), Super Carrier (A major).  Pitched clips sit in their map's key.
# ===========================================================================
def midi(m):
    return 440.0 * 2.0 ** ((m - 69) / 12.0)


def bell_modes(f, tau):
    """A cast bell: hum, prime, minor tierce, quint, nominal and the upper partials."""
    return [(f * 0.5, 0.55, tau * 1.4), (f, 1.0, tau), (f * 1.2, 0.65, tau * 0.8), (f * 1.5, 0.35, tau * 0.6),
            (f * 2.0, 0.75, tau * 0.5), (f * 2.52, 0.3, tau * 0.35), (f * 2.67, 0.28, tau * 0.3),
            (f * 3.01, 0.25, tau * 0.25), (f * 4.07, 0.15, tau * 0.15), (f * 5.43, 0.08, tau * 0.1)]


def tine(r, f, dur, tau=0.9):
    """A music-box comb tooth plucked by a pin: a cantilever's modes (1 : 6.27 : 17.55) and a tick."""
    t = tv(dur)
    tau *= (523.0 / f) ** 0.35
    x = modes(t, [(f, 1.0, tau), (f * 2.0, 0.05, tau * 0.4), (f * 6.27, 0.22, tau * 0.12),
                  (f * 17.55, 0.06, tau * 0.03)], r, 0.0015)
    return taper(x + 0.15 * click(r, dur, 2000, 9000, 0.0015), 0.05)


def groan(r, secs, f0, spec_scale=1.0, rate=(18.0, 45.0)):
    """A slow wooden groan: stick-slip swelling up and back through a timber's resonances."""
    lo, hi = rate
    g = creak(r, secs, lambda u: lo + (hi - lo) * np.sin(np.pi * u) ** 1.5,
              [(f0 * spec_scale, 1.0, 0.03), (f0 * 2.3 * spec_scale, 0.7, 0.02),
               (f0 * 4.9 * spec_scale, 0.4, 0.012), (f0 * 9.1 * spec_scale, 0.2, 0.006)])
    return taper(g * np.sin(np.pi * np.linspace(0, 1, len(g))) ** 0.8, 0.02)


def cannon_boom(r, secs, f0=70.0, size=1.0):
    """A black-powder gun: a sharp crack, a deep pressure thump, a smoky blast and a rolling tail."""
    t = tv(secs)
    n = len(t)
    x = 0.9 * thud(t, f0 * 1.6, f0 * 0.55, 0.12, 0.16 * size, harm=(0.5, 0.25))
    x += 0.9 * click(r, secs, 300, 9000, 0.004)
    x += 0.8 * unit(tilt(r.standard_normal(n), -3.0)) * env(t, 0.002, 0.07 * size)
    x += 0.5 * noise(r, n, 40, 400) * env(t, 0.01, 0.35 * size)
    return x


def turbine(t, f0, f1, glide_s, blades=(1.0, 2.0, 3.02)):
    """A jet compressor's whine: a few gliding partials."""
    f = glide(f0, f1, t, glide_s)
    x = np.zeros(len(t))
    for k, a in zip(blades, (1.0, 0.5, 0.25)):
        x += a * tone(f * k)
    return unit(x)


def gen_manor():
    # a phantom wavering in the air: pale D-minor tones drifting in and out of tune with a slow,
    # uneven tremolo, over a breathy, hollow band that sighs with them
    name = "manor_phantom_waver"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = np.zeros(n)
    for m, a in ((74, 1.0), (77, 0.7), (81, 0.55), (86, 0.3)):
        vib = 1.0 + 0.009 * np.sin(TAU * r.uniform(4.0, 6.5) * t + r.uniform(0, TAU))
        x += a * tone(midi(m) * vib) * (0.6 + 0.4 * np.sin(TAU * r.uniform(5, 9) * t + r.uniform(0, TAU)))
    breath = unit(svf(r.standard_normal(n), 900 * 2.0 ** (0.6 * np.sin(TAU * 2.2 * t)), 5.0))
    save(name, space(r, (unit(x) + 0.4 * breath) * np.sin(np.pi * t / dur(name)) ** 1.5, 1.4, 0.3),
         fin=0.02, fout=0.1)

    # a phantom forming / fading: a breath sweeping up (down) and a cluster of detuned tones
    # gliding into (out of) a D-minor chord, with a glassy ping as it takes (loses) shape
    for name, up in (("manor_phantom_form", True), ("manor_phantom_fade", False)):
        r = rng(name)
        t = tv(dur(name))
        n = len(t)
        d = dur(name)
        k = np.clip(t / (d * 0.7), 0, 1) if up else np.clip(t / d, 0, 1)
        x = np.zeros(n)
        for m in (62, 69, 74, 77, 81):
            spread = r.uniform(-1.0, 1.0) * 0.06
            f = midi(m) * (1.0 + spread * ((1.0 - k) if up else k))
            x += tone(f) * r.uniform(0.5, 1.0)
        shape = (np.sin(0.5 * np.pi * k) ** 2 * np.exp(-np.maximum(t - 0.7 * d, 0) / 0.06)) if up else \
            (1.0 - k) ** 1.5 * np.minimum(t / 0.03, 1.0)
        breath = unit(svf(r.standard_normal(n), glide(400, 2600, t, d) if up else glide(2600, 350, t, d), 3.0))
        x = unit(x) * shape + 0.5 * breath * shape
        ping = modes(tv(0.4), [(midi(86), 1.0, 0.12), (midi(86) * 2.32, 0.4, 0.05), (midi(86) * 4.25, 0.2, 0.02)])
        place(x, 0.56 if up else 0.0, ping, 0.35)
        save(name, space(r, x, 1.4, 0.35), fin=0.01, fout=0.08)

    # a portrait's eyes snapping open: a low swell of dread (D2 and A2 gliding up a little), a thin
    # sting a tritone off, a dry canvas creak and a sucked-in breath
    name = "manor_gaze_open"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    low = hum_stack(n, midi(38), 8, 1.2, 1.0) * 0.6 + hum_stack(n, midi(45) * 1.003, 6, 1.3, 1.0) * 0.4
    swell = np.minimum(t / 0.12, 1.0) * np.exp(-np.maximum(t - 0.12, 0) / 0.25)
    sting = tone(midi(80) * (1.0 + 0.004 * np.sin(TAU * 6 * t)), t) + 0.5 * tone(midi(86), t)
    x = unit(low) * swell + 0.25 * sting * env(t, 0.03, 0.2)
    x += 0.4 * unit(svf(r.standard_normal(n), glide(3000, 700, t, 0.3), 4.0)) * env(t, 0.08, 0.1)
    cr = creak(r, 0.15, lambda u: 90.0, [(700, 1.0, 0.01), (1600, 0.6, 0.006), (3100, 0.3, 0.004)])
    place(x, 0.0, cr * np.hanning(len(cr)), 0.35)
    save(name, space(r, x, 1.2, 0.3), fin=0.004, fout=0.1)

    # the portrait's gaze held on you: a dark, beating drone (D2 against a slightly sharp copy),
    # a hollow formant breathing through it and a thin whine pulsing twice a second
    name = "manor_gaze_hum"
    r = rng(name)
    n = ns(dur(name))
    a = hum_stack(n, cyc(midi(38), n), 10, 1.1, 1.2, r)
    b = hum_stack(n, cyc(midi(38) * 1.006, n), 8, 1.2, 1.0, r)
    form = unit(csvf(r.standard_normal(n), 600 * 2.0 ** (0.5 * clfo(n, 1)), 6.0))
    whine = np.sin(TAU * cyc(midi(86), n) * np.arange(n) / SR) * (0.6 + 0.4 * clfo(n, 3))
    air = cnoise(r, n, 2000, 7000) * (0.7 + 0.3 * crand(r, n, 6))
    save_loop(name, unit(a + 0.8 * b) + 0.35 * form + 0.12 * whine + 0.08 * air)

    # a chandelier's chain swinging: the links groaning against each other and a few small clinks
    name = "manor_chain_creak"
    r = rng(name)
    t = tv(dur(name))
    x = np.zeros(len(t))
    cr = creak(r, 0.6, lambda u: 30.0 + 50.0 * np.sin(np.pi * u),
               [(r.uniform(850, 950), 1.0, 0.012), (r.uniform(2000, 2300), 0.7, 0.008), (3400, 0.4, 0.005)])
    place(x, 0.05, cr * np.sin(np.pi * np.linspace(0, 1, len(cr))), 0.8)
    for _ in range(5):
        tj = r.uniform(0.1, 0.6)
        place(x, tj, modes(tv(0.15), bar_modes(r.uniform(1900, 2600), 0.03), r, 0.02, hard=7000), r.uniform(0.1, 0.3))
    save(name, space(r, x, 1.2, 0.3), fin=0.004, fout=0.1)

    # possessed furniture: slow wooden groans and knocks that repeat round the loop, a restless
    # rattle, over a faint draught
    name = "manor_possessed_creak"
    r = rng(name)
    n = ns(dur(name))
    x = np.zeros(n)
    for t0, secs, f0 in ((0.1, 0.6, 150.0), (0.8, 0.55, 190.0)):
        cplace(x, t0, groan(r, secs, f0), r.uniform(0.7, 1.0))
    for t0 in (0.72, 1.4):
        cplace(x, t0, thud(tv(0.12), 160, 90, 0.02, 0.025) + 0.4 * click(r, 0.12, 400, 3000, 0.003), 0.4)
    rattle = np.zeros(n)
    grains(r, rattle, 30, 0.0, dur(name), 600, 2500, 0.001, 0.004, 1.0, wrap=True)
    bed = cnoise(r, n, 100, 1200) * (0.7 + 0.3 * crand(r, n, 4))
    save_loop(name, unit(x) + 0.25 * unit(rattle) + 0.15 * bed)

    # a music box playing a little waltz in D minor, 3/4 at 200 bpm, four bars (Dm, Gm, A7, Dm):
    # a bass note on each downbeat, a dyad on beats two and three, the tune over it, tines ringing
    # across the wrap, the pins' ticks and the soft whirr of the spring and the air brake
    name = "manor_waltz_box"
    r = rng(name)
    n = ns(dur(name))
    beat = dur(name) / 12.0
    x = np.zeros(n)
    bass = (62, 55, 57, 62)
    dyads = ((65, 69), (70, 74), (67, 73), (65, 69))
    for bar in range(4):
        cplace(x, bar * 3 * beat, tine(r, midi(bass[bar]), 1.6), 0.6)
        for b in (1, 2):
            for m in dyads[bar]:
                cplace(x, (bar * 3 + b) * beat + r.uniform(0, 0.004), tine(r, midi(m), 1.0, 0.5), 0.28)
    for b, m in ((0, 81), (2, 86), (3, 82), (4, 79), (5, 82), (6, 81), (7, 85), (8, 88), (9, 86), (11, 81)):
        cplace(x, b * beat + r.uniform(0, 0.006), tine(r, midi(m), 1.6), 0.8)
    ticks = np.zeros(n)
    for b in range(12):
        cplace(ticks, b * beat + 0.15, taper(click(r, 0.01, 2500, 8000, 0.0006)), 0.3)
    whirr = cnoise(r, n, 300, 2500) * (0.8 + 0.2 * clfo(n, 24))
    save_loop(name, unit(x) + 0.05 * unit(ticks) + 0.025 * whirr)

    # a floorboard giving a long creak under a foot
    name = "manor_board_creak"
    r = rng(name)
    x = np.zeros(ns(dur(name)))
    place(x, 0.02, groan(r, 0.45, r.uniform(210, 250), rate=(25.0, 70.0)), 1.0)
    save(name, space(r, x, 1.0, 0.25), fin=0.004, fout=0.08)

    # the rotten board snapping: a splintering crack through the wood's modes, fibres tearing,
    # a dull drop into the void below
    name = "manor_board_snap"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = 0.9 * click(r, dur(name), 800, 9000, 0.004)
    x += 0.6 * modes(t, [(r.uniform(240, 280), 1.0, 0.04), (r.uniform(610, 680), 0.7, 0.025),
                         (r.uniform(1300, 1500), 0.5, 0.012), (r.uniform(2600, 3000), 0.3, 0.006)], r)
    grains(r, x, 40, 0.0, 0.18, 1500, 7000, 0.0006, 0.003, 0.4, decay=0.06)
    tear = creak(r, 0.15, lambda u: 200.0, [(900, 1.0, 0.006), (2100, 0.6, 0.004)])
    place(x, 0.01, tear * np.linspace(1, 0, len(tear)), 0.4)
    place(x, 0.2, thud(tv(0.3), 140, 70, 0.03, 0.05), 0.4)
    save(name, space(r, x, 1.0, 0.25), fin=0.0008, fout=0.1)

    # a coffin lid slamming down: a heavy wooden thud, the box booming, the lid's rattle and
    # the crypt answering
    name = "manor_coffin_slam"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = thud(t, 120, 58, 0.05, 0.1, harm=(0.5, 0.2)) + 0.6 * click(r, dur(name), 300, 5000, 0.004)
    x += 0.5 * modes(t, plate_modes(r.uniform(140, 170), 2.4, 0.08, 8, r=r), r, 0.0, hard=2500)
    for j in range(3):
        place(x, 0.06 + 0.05 * j + r.uniform(0, 0.02), thud(tv(0.08), 200, 120, 0.01, 0.015) +
              0.4 * click(r, 0.08, 500, 4000, 0.002), 0.3 / (j + 1))
    save(name, space(r, x, 1.8, 0.4, 100, 5000), fin=0.0008, fout=0.2)

    # the manor's great bell: a D3 minor-third bell struck once, humming on
    name = "manor_bell_toll"
    r = rng(name)
    t = tv(dur(name))
    x = modes(t, bell_modes(midi(62), 0.9), r, 0.002, hard=2500)
    x += 0.4 * click(r, dur(name), 500, 5000, 0.003) + 0.3 * thud(t, 90, 70, 0.05, 0.05)
    x *= 1.0 + 0.15 * np.sin(TAU * 2.2 * t)          # the hum and prime beating as it swings
    save(name, space(r, x, 2.2, 0.3, 100, 6000), fin=0.0008, fout=0.4)

    # a haunted mirror: a quick glassy arpeggio up a D-minor chord, each note a thin glass ring,
    # with a shimmer over it
    name = "manor_mirror_chime"
    r = rng(name)
    t = tv(dur(name))
    x = np.zeros(len(t))
    for j, m in enumerate((86, 89, 93, 98)):
        f = midi(m)
        place(x, j * 0.07, modes(tv(0.8), [(f, 1.0, 0.3), (f * 2.32, 0.35, 0.1), (f * 4.25, 0.15, 0.04)], r, 0.002),
              1.0 - 0.12 * j)
    x += 0.08 * noise(r, len(t), 5000, 12000) * env(t, 0.05, 0.3)
    save(name, space(r, x, 1.6, 0.35, 300, 9000), fin=0.002, fout=0.15)


def gen_armada():
    # a cannon's fuse burning down: a spitting, sizzling hiss with bright sparks and pops
    name = "armada_cannon_fuse"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    hiss = noise(r, n, 2500, 11000) * (0.5 + 0.5 * np.abs(noise(r, n, None, 30)))
    x = 0.6 * hiss + 0.8 * unit(crackle(r, dur(name), 160, 2000, 10000))
    grains(r, x, 20, 0.0, dur(name), 800, 3000, 0.001, 0.004, 0.4)
    save(name, x * np.minimum(t / 0.03, 1.0), fin=0.01, fout=0.1)

    # the cannon firing: a crack, a deep thump and a smoky blast, the carriage recoiling back on
    # its trucks, and the shot rolling off the clouds
    name = "armada_cannon_fire"
    r = rng(name)
    x = cannon_boom(r, dur(name), 66.0, 1.2)
    place(x, 0.09, thud(tv(0.3), 150, 80, 0.03, 0.05) + 0.4 * click(r, 0.3, 300, 3000, 0.004), 0.35)
    save(name, space(r, x, 1.8, 0.4, 80, 5000, predelay=0.03), fin=0.0005, fout=0.25)

    # the ball hitting home: a heavy thud through the timbers, a splintering crack, the deck
    # boards booming and splinters raining down
    name = "armada_cannon_impact"
    r = rng(name)
    t = tv(dur(name))
    x = thud(t, 130, 60, 0.06, 0.09, harm=(0.5, 0.2)) + 0.8 * click(r, dur(name), 600, 9000, 0.005)
    x += 0.45 * modes(t, plate_modes(r.uniform(160, 200), 3.0, 0.07, 8, r=r), r, 0.0, hard=3000)
    grains(r, x, 50, 0.01, 0.5, 1200, 7000, 0.0008, 0.004, 0.35, decay=0.15)
    save(name, space(r, x, 1.2, 0.3), fin=0.0005, fout=0.15)

    # a ship's hull working in the storm: deep timber groans coming round, the rigging's creak
    # and water sloshing in the bilge
    name = "armada_hull_creak"
    r = rng(name)
    n = ns(dur(name))
    x = np.zeros(n)
    cplace(x, 0.05, groan(r, 0.8, 95.0, rate=(14.0, 34.0)), 1.0)
    cplace(x, 0.9, groan(r, 0.5, 140.0, rate=(20.0, 50.0)), 0.6)
    slosh = cnoise(r, n, 150, 1500) * (0.5 + 0.5 * clfo(n, 1, 0.5)) ** 2
    bed = cnoise(r, n, 40, 250) * (0.8 + 0.2 * crand(r, n, 3))
    save_loop(name, unit(x) + 0.3 * slosh + 0.25 * bed)

    # a rope swing's creak: the rope fibres groaning round the spar at each end of the swing
    name = "armada_swing_creak"
    r = rng(name)
    x = np.zeros(ns(dur(name)))
    cr = creak(r, 0.5, lambda u: 40.0 + 60.0 * np.sin(np.pi * u),
               [(r.uniform(380, 440), 1.0, 0.02), (r.uniform(900, 1000), 0.6, 0.012), (1900, 0.3, 0.006)])
    place(x, 0.03, cr * np.sin(np.pi * np.linspace(0, 1, len(cr))), 1.0)
    save(name, space(r, x, 0.9, 0.2), fin=0.004, fout=0.1)

    # a lightning rod charging: an electric buzz rising (E2 up two octaves), crackle thickening and
    # a hiss of corona building
    name = "armada_rod_charge"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    f = glide(midi(40), midi(64), t, dur(name))
    ph = np.cumsum(f) / SR
    saw = sum(np.sin(TAU * k * ph) / k for k in range(1, 20))
    grow = np.clip(t / dur(name), 0, 1) ** 1.5
    x = 0.7 * unit(saw) * grow + 0.4 * noise(r, n, 3000, 11000) * grow
    cr = crackle(r, dur(name), 250, 2000, 10000)
    x += 0.7 * unit(cr) * grow
    save(name, x, fin=0.01, fout=0.03)

    # lightning hitting the rod: a searing crack, an electric sizzle, and thunder right on top of it
    name = "armada_lightning_strike"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = 1.0 * click(r, dur(name), 200, 12000, 0.006) + 0.5 * unit(crackle(r, 0.15, 150, 2000, 11000, n=n))
    x += 0.3 * buzz_wave(midi(40), n, 30) * env(t, 0.001, 0.08)
    x += 0.9 * unit(tilt(r.standard_normal(n), -4.0)) * env(t, 0.03, 0.35) * (1.0 + 0.4 * noise(r, n, None, 8))
    x += 0.6 * thud(t, 70, 38, 0.2, 0.3, harm=(0.4, 0.2))
    save(name, space(r, x, 1.8, 0.35, 60, 5000, predelay=0.04), fin=0.0005, fout=0.3)

    # a sky ship's propeller: the blades chopping the air sixteen times a second, a thrumming
    # E2 engine under it and the wash of air
    name = "armada_prop_loop"
    r = rng(name)
    n = ns(dur(name))
    chop = (0.5 + 0.5 * clfo(n, 16)) ** 4
    air = cnoise(r, n, 200, 3000)
    engine = hum_stack(n, cyc(midi(40), n), 12, 1.0, 1.3, r) * (0.85 + 0.15 * clfo(n, 16))
    wash = cnoise(r, n, 80, 600)
    save_loop(name, 0.8 * air * (0.3 + chop) + 0.5 * engine + 0.35 * wash)

    # the propeller spinning up from rest: the chop speeding up and the engine climbing to pitch
    name = "armada_prop_spinup"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    rate = 2.0 + 14.0 * np.clip(t / 0.8, 0, 1) ** 0.7
    chop = (0.5 + 0.5 * np.cos(TAU * np.cumsum(rate) / SR)) ** 4
    eng_f = midi(40) * rate / 16.0
    engine = sum(np.sin(TAU * k * np.cumsum(eng_f) / SR) / k for k in range(1, 12))
    x = 0.8 * noise(r, n, 200, 3000) * (0.3 + chop) + 0.4 * unit(engine) + 0.3 * click(r, dur(name), 200, 2000, 0.02)
    save(name, x * np.minimum(t / 0.05, 1.0), fin=0.01, fout=0.15)

    # a mast leaning before it falls: a long, deep groan of the timber
    name = "armada_mast_creak"
    r = rng(name)
    x = np.zeros(ns(dur(name)))
    place(x, 0.02, groan(r, 0.8, 110.0, rate=(12.0, 38.0)), 1.0)
    grains(r, x, 20, 0.3, 0.8, 1500, 5000, 0.0008, 0.003, 0.15)
    save(name, space(r, x, 1.3, 0.25), fin=0.004, fout=0.1)

    # the mast crashing down: fibres splintering, a huge thud onto the deck, the planks booming,
    # the rigging snapping and debris clattering
    name = "armada_mast_crash"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = np.zeros(n)
    grains(r, x, 60, 0.0, 0.15, 1500, 8000, 0.0006, 0.003, 0.6)
    place(x, 0.12, thud(tv(1.0), 100, 45, 0.1, 0.18, harm=(0.5, 0.25)) + 0.8 * click(r, 1.0, 300, 7000, 0.006), 1.0)
    place(x, 0.12, modes(tv(1.0), plate_modes(r.uniform(120, 150), 3.5, 0.1, 9, r=r), r, 0.0, hard=2500), 0.5)
    for _ in range(3):
        tj = r.uniform(0.15, 0.35)
        place(x, tj, modes(tv(0.3), [(r.uniform(150, 250), 1.0, 0.05), (r.uniform(500, 700), 0.4, 0.02)], r), 0.35)
    grains(r, x, 60, 0.15, 0.9, 800, 5000, 0.001, 0.005, 0.3, decay=0.25)
    save(name, space(r, x, 1.6, 0.35, 80, 5000), fin=0.004, fout=0.25)

    # a winch hauling: its pawl clacking over the ratchet ten times a second, a gear whine, the
    # rope creaking round the drum and a low rumble
    name = "armada_winch_loop"
    r = rng(name)
    n = ns(dur(name))
    x = np.zeros(n)
    for k in range(10):
        cplace(x, k * 0.1 + r.uniform(0, 0.004), taper(modes(tv(0.05), bar_modes(r.uniform(1400, 1600), 0.012), r, 0.02)) +
               0.5 * taper(click(r, 0.05, 800, 6000, 0.002)), r.uniform(0.7, 1.0))
    whine = hum_stack(n, cyc(midi(52), n), 6, 1.3, 1.0, r) * (0.7 + 0.3 * clfo(n, 2))
    rope = np.zeros(n)
    cplace(rope, 0.1, groan(r, 0.8, 330.0, rate=(40.0, 70.0)), 1.0)
    save_loop(name, unit(x) + 0.2 * whine + 0.3 * unit(rope) + 0.2 * cnoise(r, n, 60, 400))

    # the ship's bell rung twice, "ding-ding": a small brass bell on E5
    name = "armada_ship_bell"
    r = rng(name)
    t = tv(dur(name))
    x = np.zeros(len(t))
    for t0, g in ((0.0, 1.0), (0.32, 0.9)):
        place(x, t0, modes(tv(1.4 - t0), bell_modes(midi(76), 0.5), r, 0.001, hard=5000) +
              0.3 * click(r, 1.4 - t0, 2000, 9000, 0.001), g)
    save(name, space(r, x, 1.4, 0.25, 200, 8000), fin=0.0008, fout=0.2)

    # the victory salute: three guns fired in turn, each rolling off the clouds
    name = "armada_salute"
    r = rng(name)
    x = np.zeros(ns(dur(name)))
    for j, t0 in enumerate((0.0, 0.38, 0.76)):
        place(x, t0, cannon_boom(r, dur(name) - t0, 70.0 + 6 * j, 0.9), 1.0 - 0.1 * j)
    save(name, space(r, x, 1.8, 0.4, 80, 5000, predelay=0.04), fin=0.0005, fout=0.25)


def gen_candy():
    # jelly bouncing: a wobbling "boing" gliding C3 up to G3 with a decaying 11 Hz jiggle, a wet slap
    name = "candy_jelly_boing"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    f = glide(midi(48), midi(55), t, 0.12) * (1.0 + 0.06 * np.sin(TAU * 11 * t) * np.exp(-t / 0.15))
    x = (tone(f) + 0.3 * tone(2 * f) + 0.1 * tone(3 * f)) * env(t, 0.004, 0.14)
    x += 0.5 * noise(r, n, 300, 3000) * env(t, 0.001, 0.015)
    x += 0.3 * unit(svf(r.standard_normal(n), glide(1500, 400, t, 0.1), 4.0)) * env(t, 0.002, 0.05)
    save(name, x, fin=0.001, fout=0.08)

    # a jack-in-the-box being wound: the crank's ratchet clicking and its tune plinking up C major
    name = "candy_jack_wind"
    r = rng(name)
    x = np.zeros(ns(dur(name)))
    for k in range(6):
        place(x, 0.02 + k * 0.12, taper(modes(tv(0.04), bar_modes(r.uniform(1800, 2200), 0.008), r, 0.02)) +
              0.4 * taper(click(r, 0.04, 1000, 7000, 0.0015)), 0.5)
    for k, m in enumerate((72, 76, 79, 84)):
        place(x, 0.02 + k * 0.18, tine(r, midi(m), 0.5, 0.25), 0.6)
    save(name, x, fin=0.001, fout=0.1)

    # the jack popping out: a latch click, a springy "sproing" (a C4 tone gliding up with a fast
    # wobble), a cork-like pop and a bright C-major ding
    name = "candy_jack_pop"
    r = rng(name)
    t = tv(dur(name))
    x = 0.4 * click(r, dur(name), 1500, 8000, 0.001)
    tt = tv(0.5)
    f = glide(midi(60), midi(72), tt, 0.1) * (1.0 + 0.08 * np.sin(TAU * 22 * tt) * np.exp(-tt / 0.12))
    place(x, 0.01, (tone(f) + 0.4 * tone(2.01 * f)) * env(tt, 0.002, 0.12), 0.7)
    place(x, 0.02, bubble(300, 0.1, 0.012, 1.2) + 0.5 * click(r, 0.1, 500, 4000, 0.003), 0.8)
    for m in (84, 88, 91):
        place(x, 0.06, modes(tv(0.6), bar_modes(midi(m), 0.25), r, 0.0, hard=6000), 0.2)
    save(name, x, fin=0.0008, fout=0.1)

    # a tin soldier marching: four stiff tin-foot clacks a loop (at 150 steps a minute), a drum tap
    # on each, the clockwork ticking eight times a second inside and its spring whirr
    name = "candy_soldier_march"
    r = rng(name)
    n = ns(dur(name))
    x = np.zeros(n)
    for k in range(4):
        f1 = 1700.0 if k % 2 == 0 else 1850.0
        foot = modes(tv(0.1), [(f1, 1.0, 0.02), (f1 * 1.58, 0.6, 0.012), (f1 * 2.4, 0.4, 0.008), (420, 0.6, 0.02)], r, 0.01)
        drum = noise(r, ns(0.1), 180, 3000) * np.exp(-tv(0.1) / 0.02) + tone(180, tv(0.1)) * np.exp(-tv(0.1) / 0.03)
        cplace(x, k * 0.4, taper(foot + 0.5 * taper(drum)), 1.0 if k % 2 == 0 else 0.85)
    for k in range(13):
        cplace(x, k * dur(name) / 13 + 0.05, taper(click(r, 0.01, 3000, 9000, 0.0005)), 0.12)
    whirr = cnoise(r, n, 800, 4000) * (0.6 + 0.4 * clfo(n, 26))
    save_loop(name, unit(x) + 0.05 * whirr)

    # the soldier's about-turn: a quick clockwork whirr and a tin clank as it pivots
    name = "candy_soldier_turn"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = 0.4 * noise(r, n, 1000, 5000) * (0.5 + 0.5 * np.sin(TAU * 40 * t)) * env(t, 0.02, 0.1)
    place(x, 0.15, modes(tv(0.2), [(1600, 1.0, 0.04), (2530, 0.6, 0.025), (3900, 0.4, 0.012)], r, 0.01) +
          0.4 * click(r, 0.2, 1500, 8000, 0.002), 1.0)
    save(name, x, fin=0.004, fout=0.08)

    # a toy steam train: four chuffs a loop, the wheels clacking over the rail joins, the
    # boiler's rumble and a little steam hiss
    name = "candy_train_chug"
    r = rng(name)
    n = ns(dur(name))
    x = np.zeros(n)
    for k in range(4):
        tt = tv(0.3)
        chuff = noise(r, len(tt), 300, 4000) * env(tt, 0.01, 0.07) + 0.4 * noise(r, len(tt), 80, 400) * env(tt, 0.005, 0.05)
        cplace(x, k * 0.4, taper(chuff), 1.0 if k % 2 == 0 else 0.8)
    for t0 in (0.55, 0.65, 1.35, 1.45):
        cplace(x, t0, taper(thud(tv(0.06), 240, 150, 0.01, 0.012) + 0.4 * click(r, 0.06, 1500, 6000, 0.001)), 0.5)
    rumble = cnoise(r, n, 50, 300) * (0.8 + 0.2 * clfo(n, 4))
    hiss = cnoise(r, n, 3000, 9000)
    save_loop(name, unit(x) + 0.2 * rumble + 0.05 * hiss)

    # the train's whistle: a C-major chord (C6, E6, G6) blown through a steamy pipe, scooping up
    # into pitch, breathy, with a short toot then a longer one
    name = "candy_train_whistle"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = np.zeros(n)
    for t0, d in ((0.0, 0.25), (0.35, 0.8)):
        tt = tv(d)
        m = len(tt)
        scoop = 1.0 - 0.03 * np.exp(-tt / 0.04)
        e = np.minimum(tt / 0.03, 1.0) * np.minimum((d - tt) / 0.06, 1.0)
        v = np.zeros(m)
        for mm, a in ((84, 1.0), (88, 0.8), (91, 0.7)):
            f = midi(mm) * scoop * (1.0 + 0.003 * np.sin(TAU * 5.5 * tt))
            v += a * (tone(f) + 0.2 * tone(2 * f))
        steam = unit(svf(r.standard_normal(m), midi(88), 8.0))
        place(x, t0, (unit(v) + 0.35 * steam + 0.2 * noise(r, m, 2000, 9000)) * e, 1.0)
    save(name, space(r, x, 1.2, 0.3), fin=0.004, fout=0.12)

    # a gumball dropping out of the machine: the coin wheel clunking round, then the ball
    # bouncing down the chute, each hop shorter
    name = "candy_gumball_drop"
    r = rng(name)
    x = np.zeros(ns(dur(name)))
    place(x, 0.0, thud(tv(0.15), 300, 180, 0.02, 0.03) + 0.5 * click(r, 0.15, 800, 5000, 0.003), 0.7)
    t0, gap, g = 0.12, 0.14, 1.0
    while t0 < 0.55:
        place(x, t0, modes(tv(0.08), [(r.uniform(850, 950), 1.0, 0.012), (2300, 0.4, 0.006), (4100, 0.2, 0.003)], r) +
              0.3 * click(r, 0.08, 1500, 7000, 0.001), g)
        t0 += gap
        gap *= 0.72
        g *= 0.75
    save(name, x, fin=0.001, fout=0.06)

    # a gumball rolling down a candy chute: a hollow rumble, a knock at each seam of the chute
    # and the ball's own little rattle
    name = "candy_gumball_roll"
    r = rng(name)
    n = ns(dur(name))
    rumble = csvf(r.standard_normal(n), 500 * (1.0 + 0.1 * clfo(n, 6)), 2.0)
    knocks = np.zeros(n)
    for k in range(8):
        cplace(knocks, k * 0.15, taper(modes(tv(0.05), [(r.uniform(700, 800), 1.0, 0.01), (1900, 0.4, 0.005)], r)), 1.0)
    rattle = np.zeros(n)
    grains(r, rattle, 60, 0.0, dur(name), 1500, 5000, 0.001, 0.003, 1.0, wrap=True)
    save_loop(name, unit(rumble) + 0.5 * unit(knocks) + 0.2 * unit(rattle))

    # a gumball plopping into syrup: a gloopy plunk, a thick splash and a few slow bubbles
    name = "candy_gumball_splash"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = 0.5 * thud(t, 160, 80, 0.04, 0.05)
    place(x, 0.0, bubble(260, 0.25, 0.04, 1.4), 0.8)
    x += 0.6 * unit(svf(r.standard_normal(n), glide(2500, 600, t, 0.2), 3.0)) * env(t, 0.004, 0.08)
    for _ in range(6):
        place(x, r.uniform(0.12, 0.6), bubble(r.uniform(300, 600), 0.12, 0.02, 0.8), r.uniform(0.1, 0.3))
    save(name, x, fin=0.0008, fout=0.1)

    # a confetti popper: a pop, a flurry of paper fluttering down and a twinkle of C-major bells
    name = "candy_confetti"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = 0.9 * click(r, dur(name), 400, 6000, 0.004)
    place(x, 0.0, bubble(180, 0.1, 0.015, 1.5), 0.6)
    flutter = np.zeros(n)
    grains(r, flutter, 220, 0.02, 0.8, 2000, 9000, 0.0005, 0.002, 1.0, decay=0.3)
    x += 0.5 * unit(flutter)
    for j, m in enumerate((84, 88, 91, 96)):
        place(x, 0.05 + 0.06 * j, modes(tv(0.5), bar_modes(midi(m), 0.2), r, 0.0, hard=8000), 0.15)
    save(name, space(r, x, 1.0, 0.2, 300, 9000), fin=0.0008, fout=0.12)

    # fireworks: a rocket whistling up, a bang, and the stars crackling as they fall
    name = "candy_fireworks"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = np.zeros(n)
    tt = tv(0.45)
    wh = unit(svf(r.standard_normal(len(tt)), glide(1200, 3200, tt, 0.45), 20.0)) * np.minimum(tt / 0.05, 1.0)
    place(x, 0.0, taper(wh), 0.4)
    place(x, 0.45, cannon_boom(r, 1.0, 90.0, 0.7), 1.0)
    cr = np.zeros(n)
    for _ in range(260):
        t0 = 0.5 + r.gamma(2.0, 0.18)
        if t0 < dur(name) - 0.02:
            place(cr, t0, noise(r, ns(0.004), 2500, 11000) * np.exp(-tv(0.004) / 0.0007), r.uniform(0.2, 1.0) ** 2)
    x += 0.5 * unit(cr)
    save(name, space(r, x, 1.6, 0.35, 100, 7000, predelay=0.03), fin=0.004, fout=0.25)


def gen_carrier():
    # the steam catapult venting: a loud hiss of steam bursting up out of the track slot
    name = "carrier_cat_hiss"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = noise(r, n, 800, 10000) * (0.85 + 0.15 * noise(r, n, None, 20)) + 0.4 * noise(r, n, 150, 900)
    save(name, x * np.minimum(t / 0.04, 1.0) * np.exp(-t / 0.35), fin=0.004, fout=0.1)

    # the catapult firing: a huge steam thump, the shuttle screaming down the track (a whoosh
    # rising and the rails singing) and the water brake catching it with a clunk and hiss
    name = "carrier_cat_launch"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = 0.9 * thud(t, 110, 50, 0.1, 0.12, harm=(0.5, 0.2)) + 0.8 * noise(r, n, 300, 9000) * env(t, 0.002, 0.08)
    x += 0.7 * whoosh(r, dur(name), 300, 2500, 1200, 0.7, 0.3)
    x += 0.2 * unit(svf(r.standard_normal(n), glide(400, 2000, t, 0.8), 25.0)) * np.sin(np.pi * np.clip(t / 0.9, 0, 1))
    place(x, 0.85, thud(tv(0.35), 140, 70, 0.03, 0.06) + 0.6 * click(r, 0.35, 500, 5000, 0.004) +
          0.4 * noise(r, ns(0.35), 1000, 9000) * np.exp(-tv(0.35) / 0.1), 0.8)
    save(name, space(r, x, 1.2, 0.25, 80, 6000, predelay=0.02), fin=0.0005, fout=0.15)

    # the shuttle being hauled back: a rumble along the track, a hydraulic whine falling, a clunk
    name = "carrier_cat_retract"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = 0.6 * noise(r, n, 80, 800) * np.sin(np.pi * np.clip(t / 0.75, 0, 1))
    x += 0.3 * turbine(t, 900, 500, 0.75) * np.sin(np.pi * np.clip(t / 0.75, 0, 1))
    place(x, 0.72, thud(tv(0.18), 160, 90, 0.02, 0.03) + 0.5 * click(r, 0.18, 600, 6000, 0.003), 0.8)
    save(name, x, fin=0.01, fout=0.08)

    # a jet engine spooling up: the compressor whine climbing, the roar swelling under it
    name = "carrier_jet_spool"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    k = np.clip(t / dur(name), 0, 1)
    x = 0.5 * turbine(t, 600, 3200, dur(name)) * (0.3 + 0.7 * k)
    x += 0.8 * unit(tilt(r.standard_normal(n), -2.0)) * k ** 1.5 + 0.4 * noise(r, n, 40, 250) * k
    save(name, x * np.minimum(t / 0.1, 1.0), fin=0.02, fout=0.1)

    # a jet at full power behind the blast deflector: a churning, tearing roar, the whine on top
    # and the deck rumbling
    name = "carrier_jet_roar"
    r = rng(name)
    n = ns(dur(name))
    roar = unit(tilt(cnoise(r, n, 60, 12000, 1), -2.0, circular=True)) * (0.8 + 0.2 * crand(r, n, 20, 0.5))
    tear = cnoise(r, n, 600, 3000) * (0.6 + 0.4 * crand(r, n, 30))
    whine = hum_stack(n, cyc(3200, n), 2, 1.0, 1.0, r)
    rumble = cnoise(r, n, 30, 150)
    save_loop(name, roar + 0.3 * tear + 0.05 * whine + 0.4 * rumble)

    # a hook catching the arresting wire: the steel cable's low twang (a stiff string, slightly
    # inharmonic) and the clank of the hook
    name = "carrier_wire_twang"
    r = rng(name)
    t = tv(dur(name))
    f0 = 55.0
    spec = [(f0 * k * np.sqrt(1 + 0.004 * k * k), 1.0 / k, 0.25 / k ** 0.4) for k in range(1, 16)]
    x = modes(t, spec, r, 0.0) * (1.0 + 0.2 * np.sin(TAU * 7 * t))
    x += 0.6 * modes(t, bar_modes(r.uniform(900, 1100), 0.05), r, 0.02) + 0.6 * click(r, dur(name), 500, 7000, 0.003)
    save(name, x, fin=0.0008, fout=0.12)

    # an aircraft elevator starting / stopping: the lock clunk and the motor winding up / down
    for name, up in (("carrier_elevator_start", True), ("carrier_elevator_stop", False)):
        r = rng(name)
        t = tv(dur(name))
        n = len(t)
        x = np.zeros(n)
        clunk = thud(tv(0.25), 130, 65, 0.03, 0.05, harm=(0.5, 0.2)) + 0.6 * click(r, 0.25, 400, 5000, 0.004)
        if up:
            place(x, 0.0, clunk, 1.0)
            k = np.clip(t / 0.5, 0, 1)
            x += 0.5 * turbine(t, 110, midi(45) * 2, 0.5, (1.0, 2.0, 4.0)) * k
        else:
            k = np.clip(1.0 - t / 0.4, 0, 1)
            x += 0.5 * turbine(t, midi(45) * 2, 110, 0.4, (1.0, 2.0, 4.0)) * k
            place(x, 0.35, clunk, 1.0)
        save(name, x, fin=0.004, fout=0.08)

    # the elevator moving: an A-pitched motor hum and the platform rumbling in its guides
    name = "carrier_elevator_hum"
    r = rng(name)
    n = ns(dur(name))
    hum = hum_stack(n, cyc(midi(45), n), 12, 1.0, 1.5, r)
    whine = np.sin(TAU * cyc(midi(81), n) * np.arange(n) / SR)
    rumble = cnoise(r, n, 50, 500) * (0.8 + 0.2 * crand(r, n, 6))
    save_loop(name, 0.6 * hum + 0.1 * whine + 0.5 * rumble)

    # the hangar door alarm: two klaxon blasts (a buzzy A4 through a horn formant)
    name = "carrier_door_klaxon"
    r = rng(name)
    x = np.zeros(ns(dur(name)))
    for t0 in (0.0, 0.5):
        tt = tv(0.4)
        m = len(tt)
        b = buzz_wave(midi(69), m, 30, 0.8)
        b = unit(svf(b, 1400.0, 2.0) + 0.5 * svf(b, 2600.0, 3.0))
        place(x, t0, b * np.minimum(tt / 0.02, 1.0) * np.minimum((0.4 - tt) / 0.03, 1.0), 1.0)
    save(name, space(r, x, 1.4, 0.3, 200, 6000), fin=0.004, fout=0.1)

    # the hangar door grinding: steel dragging on its rails (stick-slip through its resonances),
    # rollers rumbling and a deep motor
    name = "carrier_door_grind"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    g = creak(r, 1.0, lambda u: 28.0 + 20.0 * np.sin(np.pi * u),
              [(r.uniform(180, 220), 1.0, 0.03), (r.uniform(480, 540), 0.7, 0.02), (r.uniform(1150, 1300), 0.4, 0.012),
               (r.uniform(2400, 2800), 0.2, 0.006)])
    x = np.zeros(n)
    place(x, 0.05, g * np.sin(np.pi * np.linspace(0, 1, len(g))) ** 0.5, 0.8)
    x += 0.5 * noise(r, n, 40, 300) * np.sin(np.pi * t / dur(name)) + 0.3 * hum_stack(n, midi(33), 10) * np.sin(np.pi * t / dur(name))
    save(name, space(r, x, 1.4, 0.3, 80, 5000), fin=0.01, fout=0.1)

    # a jet on the catapult winding up to launch power: the whine climbing, the roar rising and the
    # afterburner lighting with a thump and a crackle
    name = "carrier_launch_spool"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    k = np.clip(t / 0.9, 0, 1)
    x = 0.4 * turbine(t, 900, 3000, 0.9) * (0.3 + 0.7 * k)
    x += 0.7 * unit(tilt(r.standard_normal(n), -2.0)) * k ** 1.5
    ab = t > 0.9
    x += ab * (0.9 * unit(tilt(r.standard_normal(n), -3.0)) + 0.4 * unit(crackle(r, dur(name), 300, 1500, 8000)))
    place(x, 0.9, thud(tv(0.3), 90, 45, 0.05, 0.08), 0.8)
    save(name, x * np.minimum(t / 0.1, 1.0), fin=0.02, fout=0.06)

    # the launch: the catapult's slam, the jet's roar blasting past and away down the deck
    name = "carrier_launch_shot"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = 0.9 * thud(t, 100, 45, 0.1, 0.12, harm=(0.5, 0.2)) + 0.6 * noise(r, n, 300, 9000) * env(t, 0.002, 0.06)
    roar = unit(tilt(r.standard_normal(n), -2.5))
    x += 0.9 * unit(svf(roar, glide(2500, 500, t, 1.0), 0.8)) * np.exp(-t / 0.5)
    x += 0.2 * turbine(t, 3000, 1800, 1.0) * np.exp(-t / 0.4)
    save(name, space(r, x, 1.4, 0.3, 60, 6000, predelay=0.03), fin=0.0005, fout=0.2)

    # a jet flying past close by: the roar sweeping in and out with the Doppler drop in its whine
    name = "carrier_launch_flyby"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = whoosh(r, dur(name), 300, 3000, 400, 0.6, 0.25, q=0.9)
    x += 0.5 * unit(tilt(r.standard_normal(n), -3.0)) * np.exp(-0.5 * ((t - 0.65) / 0.3) ** 2)
    x += 0.15 * turbine(t, 3400, 2300, 1.2) * np.exp(-0.5 * ((t - 0.6) / 0.3) ** 2)
    save(name, x, fin=0.02, fout=0.15)

    # the jet blast deflector raising / lowering: a hydraulic whine rising (falling), fluid hiss, a
    # deep clunk when it locks
    for name, up in (("carrier_jbd_raise", True), ("carrier_jbd_lower", False)):
        r = rng(name)
        t = tv(dur(name))
        n = len(t)
        body = np.sin(np.pi * np.clip(t / 0.8, 0, 1)) ** 0.5
        x = 0.4 * turbine(t, 300 if up else 520, 520 if up else 300, 0.8, (1.0, 2.0, 3.0)) * body
        x += 0.3 * noise(r, n, 2000, 8000) * body + 0.3 * noise(r, n, 60, 300) * body
        place(x, 0.78, thud(tv(0.22), 120, 60, 0.03, 0.05, harm=(0.5, 0.2)) + 0.6 * click(r, 0.22, 400, 5000, 0.003), 1.0)
        save(name, x, fin=0.02, fout=0.06)

    # an aircraft lift moving: a clunk, two A-major warning beeps and the motor hum rising
    name = "carrier_lift_move"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = 0.4 * hum_stack(n, midi(45), 10, 1.0, 1.5) * np.minimum(t / 0.3, 1.0) + 0.3 * noise(r, n, 50, 400)
    place(x, 0.0, thud(tv(0.25), 130, 65, 0.03, 0.05) + 0.5 * click(r, 0.25, 400, 5000, 0.004), 1.0)
    for t0, m in ((0.1, 81), (0.35, 85)):
        tt = tv(0.15)
        place(x, t0, (tone(midi(m), tt) + 0.3 * tone(3 * midi(m), tt)) * np.minimum(tt / 0.005, 1.0) *
              np.minimum((0.15 - tt) / 0.01, 1.0), 0.25)
    save(name, x, fin=0.004, fout=0.12)

    # the finish flyover: three jets thundering past in turn, roars overlapping, the whines
    # dropping as they go
    name = "carrier_flyover"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = np.zeros(n)
    for j, tp in enumerate((0.6, 0.8, 1.0)):
        x += whoosh(r, dur(name), 250, 2500 - 200 * j, 350, tp, 0.3, q=0.8) * (1.0 - 0.1 * j)
        x += 0.12 * turbine(t, 3300 - 100 * j, 2200, 1.5) * np.exp(-0.5 * ((t - tp) / 0.3) ** 2)
    x += 0.5 * noise(r, n, 30, 200) * np.exp(-0.5 * ((t - 0.8) / 0.4) ** 2)
    save(name, space(r, x, 1.8, 0.3, 60, 6000, predelay=0.04), fin=0.02, fout=0.25)


# ===========================================================================
# the third set of new worlds: Sakura Peaks (D minor pentatonic), Jungle Temple (A minor),
# Wild West Heist (G major), Neon City (E minor).  Pitched clips sit in their map's key.
# ===========================================================================
def bamboo_knock(r, secs, f0, hard=6000.0):
    """A hollow bamboo culm knocked: a light, woody tube with a strong first mode and a tick."""
    t = tv(secs)
    x = modes(t, [(f0, 1.0, 0.06), (f0 * 2.03, 0.45, 0.035), (f0 * 3.1, 0.3, 0.02), (f0 * 4.6, 0.18, 0.01),
                  (f0 * 6.9, 0.1, 0.005)], r, 0.01, hard)
    return taper(x + 0.3 * click(r, secs, 800, 6000, 0.0015))


def wood_knock(r, secs, f0, tau=0.03, hard=5000.0):
    """A plank or a frame knocked: three low-Q wood modes and a short contact tick."""
    t = tv(secs)
    x = modes(t, [(f0, 1.0, tau), (f0 * 2.37, 0.6, tau * 0.6), (f0 * 4.1, 0.35, tau * 0.35),
                  (f0 * 6.3, 0.15, tau * 0.2)], r, 0.03, hard)
    return taper(x + 0.35 * click(r, secs, 500, 6000, 0.002))


def coin_hit(r, secs, f0):
    """A silver coin striking another: a thin free disc's modes (1 : 1.73 : 2.33 : 3.91 : 4.11)."""
    t = tv(secs)
    spec = [(f0, 1.0, 0.18), (f0 * 1.73, 0.6, 0.12), (f0 * 2.33, 0.5, 0.09), (f0 * 3.91, 0.25, 0.05),
            (f0 * 4.11, 0.2, 0.045)]
    return taper(modes(t, spec, r, 0.01, hard=8000) + 0.2 * click(r, secs, 3000, 10000, 0.0006))


def firework_shell(r, secs, t_launch, rise, whistle=(1200.0, 3000.0), boom_f=90.0, stars=220, glitter=0.0,
                   mortar=False):
    """One shell: (a mortar's hollow "pon",) the rocket whistling up, the burst and its stars crackling."""
    x = np.zeros(ns(secs))
    if mortar:
        tt = tv(0.3)
        place(x, t_launch, taper(thud(tt, 170, 85, 0.03, 0.05) + 0.4 * noise(r, len(tt), 200, 2500) * env(tt, 0.001, 0.02)),
              0.5)
    tt = tv(rise)
    wh = unit(svf(r.standard_normal(len(tt)), glide(whistle[0], whistle[1], tt, rise), 16.0))
    place(x, t_launch, taper(wh * np.minimum(tt / 0.05, 1.0) * (0.4 + 0.6 * tt / rise), 0.02), 0.3)
    tb = t_launch + rise
    if tb < secs - 0.05:
        place(x, tb, taper(cannon_boom(r, min(1.0, secs - tb), boom_f, 0.7), 0.02), 1.0)
    cr = np.zeros(len(x))
    for _ in range(stars):
        t0 = tb + 0.04 + r.gamma(2.0, 0.16)
        if t0 < secs - 0.02:
            place(cr, t0, noise(r, ns(0.004), 2500, 10000) * np.exp(-tv(0.004) / 0.0007), r.uniform(0.2, 1.0) ** 2)
    if stars:
        x += 0.45 * unit(cr)
    if glitter:
        t = tv(secs)
        u = np.maximum(t - tb, 0.0)
        x += glitter * noise(r, len(x), 3000, 9000) * np.minimum(u / 0.08, 1.0) * np.exp(-u / 0.6) * (t > tb)
    return x


def water_roar(r, n, lo, hi, slope, churn):
    """A waterfall's body: broadband noise (tilted), churning slowly - circular, for loops."""
    return unit(tilt(cnoise(r, n, lo, hi, 1), slope, circular=True)) * (1.0 - churn + churn * crand(r, n, 30, 0.4))


def gen_sakura():
    # the bamboo's lashing creaking under the strain, just before it snaps: rope fibres groaning
    # round the culm, the hollow culm answering, and the leaves shivering
    name = "sakura_bamboo_creak"
    r = rng(name)
    x = np.zeros(ns(dur(name)))
    cr = creak(r, 0.55, lambda u: 35.0 + 60.0 * u ** 1.5,
               [(r.uniform(520, 600), 1.0, 0.02), (r.uniform(1350, 1500), 0.7, 0.012), (r.uniform(2700, 3000), 0.3, 0.006),
                (r.uniform(230, 260), 0.5, 0.03)])
    place(x, 0.04, cr * np.sin(np.pi * np.linspace(0, 1, len(cr))) ** 0.7 * np.linspace(0.6, 1.0, len(cr)), 0.8)
    fib = creak(r, 0.4, lambda u: 120.0 + 80.0 * u, [(r.uniform(1800, 2100), 1.0, 0.004), (r.uniform(3300, 3700), 0.5, 0.003)])
    place(x, 0.2, fib * np.hanning(len(fib)), 0.2)
    for t0 in (0.12, 0.42):
        place(x, t0, bamboo_knock(r, 0.25, r.uniform(480, 540), 2500), 0.25)
    grains(r, x, 60, 0.05, 0.62, 2500, 8000, 0.001, 0.004, 0.08)
    save(name, space(r, x, 0.8, 0.15, 200, 8000), fin=0.004, fout=0.1)

    # the culm whipping straight: a sharp wooden crack through its hollow tube, splinters, the
    # swish of it whipping past, the pole thrumming and the leaves thrashing
    name = "sakura_bamboo_snap"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = 0.8 * click(r, dur(name), 1200, 10000, 0.002)
    x += 0.7 * bamboo_knock(r, dur(name), r.uniform(560, 620), 9000)
    grains(r, x, 25, 0.0, 0.04, 2000, 9000, 0.0005, 0.002, 0.5)
    x += 0.45 * whoosh(r, dur(name), 400, 2600, 700, 0.07, 0.04, 1.4)
    x += 0.3 * noise(r, n, 200, 900) * (0.5 + 0.5 * np.sin(TAU * 7 * t)) * env(t, 0.03, 0.2)
    lv = np.zeros(n)
    grains(r, lv, 200, 0.05, 0.75, 2000, 9000, 0.001, 0.004, 1.0, decay=0.2)
    x += 0.3 * unit(lv)
    save(name, space(r, x, 0.9, 0.2, 200, 8000), fin=0.0005, fout=0.15)

    # the great temple bell (a bonsho) boomed by the swinging log: a soft wooden blow, a deep D with
    # its hum an octave down, the partials slightly split so it wavers as it rings, in the valley
    name = "sakura_bell_bong"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    f = midi(50)
    x = modes(t, bell_modes(f, 1.3), r, 0.0, hard=2200)
    x += 0.6 * modes(t, [(f * 0.5 * 1.004, 0.5, 1.8), (f * 1.006, 0.6, 1.1), (f * 2.0 * 1.003, 0.3, 0.6)], r)
    x = x * (1.0 + 0.12 * np.sin(TAU * 1.7 * t))
    x += 0.6 * thud(t, 120, 70, 0.02, 0.03) + 0.25 * band(click(r, dur(name), 200, 2500, 0.004), None, 2500)
    save(name, space(r, x, 2.6, 0.35, 80, 5000, predelay=0.02), fin=0.001, fout=0.5)

    # the log swinging past: a heavy, low push of air rising to the pass and falling, and the
    # ropes creaking at the top of the swing
    name = "sakura_log_whoosh"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = whoosh(r, dur(name), 150, 700, 250, 0.4, 0.15, 1.0)
    x += 0.45 * noise(r, n, 40, 200) * np.exp(-0.5 * ((t - 0.4) / 0.15) ** 2)
    cr = creak(r, 0.35, lambda u: 25.0 + 30.0 * u, [(r.uniform(300, 340), 1.0, 0.02), (r.uniform(800, 880), 0.6, 0.012),
                                                   (1900, 0.3, 0.006)])
    place(x, 0.0, cr * np.hanning(len(cr)), 0.2)
    save(name, x, fin=0.02, fout=0.12)

    # the log ramming the runner: a heavy wooden thump, the dense trunk's modes and the ropes jolting
    name = "sakura_log_thump"
    r = rng(name)
    t = tv(dur(name))
    x = 0.7 * thud(t, 110, 50, 0.05, 0.09, harm=(0.5, 0.2)) + 0.5 * click(r, dur(name), 300, 5000, 0.004)
    x += 0.85 * modes(t, [(r.uniform(170, 190), 1.0, 0.06), (r.uniform(400, 440), 0.7, 0.035), (r.uniform(740, 800), 0.45, 0.02),
                         (r.uniform(1300, 1450), 0.25, 0.01)], r, 0.0, hard=2500)
    jolt = creak(r, 0.2, lambda u: 60.0, [(r.uniform(320, 360), 1.0, 0.015), (900, 0.5, 0.008)])
    place(x, 0.05, jolt * np.hanning(len(jolt)), 0.15)
    grains(r, x, 20, 0.02, 0.3, 600, 3000, 0.002, 0.006, 0.08, decay=0.1)
    save(name, space(r, x, 0.8, 0.2, 100, 6000), fin=0.0008, fout=0.12)

    # a giant petal starting to give under you: a soft, papery sigh falling away, a rustle and a
    # faint D6 sinking to C6
    name = "sakura_petal_sink"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    sw = np.sin(np.pi * t / dur(name)) ** 1.2
    sigh = unit(svf(r.standard_normal(n), glide(2600, 900, t, 0.6), 2.5)) * sw
    rustle = np.zeros(n)
    grains(r, rustle, 150, 0.02, 0.6, 1500, 6000, 0.001, 0.004, 1.0)
    whuff = noise(r, n, 150, 600) * sw ** 2
    ping = tone(glide(midi(86), midi(84), t, 0.5), None) * np.minimum(t / 0.06, 1.0) * np.exp(-t / 0.3)
    save(name, 0.7 * sigh + 0.3 * unit(rustle) * sw + 0.35 * whuff + 0.12 * ping, fin=0.02, fout=0.12)

    # the shuriken flung off its socket: a flick, a bright "shing" and the steel star ringing
    # (paired modes, slightly split by its points, so the ring shimmers), on D6
    name = "sakura_shuriken_ring"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    f0 = midi(86)
    spec = []
    for k, (rat, a, tau) in enumerate(((1.0, 1.0, 0.4), (1.47, 0.6, 0.25), (2.09, 0.45, 0.15), (2.81, 0.3, 0.1),
                                       (3.7, 0.2, 0.06))):
        spec += [(f0 * rat, a, tau), (f0 * rat * (1.0 + 0.003 * (k + 1)), a * 0.8, tau)]
    ring = modes(t, spec, r, 0.0, hard=6000)
    shing = unit(svf(r.standard_normal(n), glide(2500, 7000, t, 0.06), 6.0)) * env(t, 0.003, 0.03)
    x = band(0.6 * ring + 0.45 * shing + 0.3 * click(r, dur(name), 1500, 9000, 0.0008), None, 11000)
    save(name, space(r, x, 0.9, 0.2, 300, 9000), fin=0.0005, fout=0.15)

    # the star spinning in flight: air chopped by its four points 24 times a loop-second, a
    # low flutter under it and the faint ring of the steel
    name = "sakura_shuriken_whir"
    r = rng(name)
    n = ns(dur(name))
    i = np.arange(n) / SR
    pulse = (0.5 + 0.5 * clfo(n, 24)) ** 3
    whir = cnoise(r, n, 700, 5000) * (0.25 + 0.75 * pulse) * (0.85 + 0.15 * crand(r, n, 6))
    low = cnoise(r, n, 150, 700) * (0.5 + 0.5 * clfo(n, 24, 1.0)) ** 2
    ring = (np.sin(TAU * cyc(midi(86), n) * i) + 0.4 * np.sin(TAU * cyc(midi(86) * 1.47, n) * i)) * (0.7 + 0.3 * clfo(n, 24))
    save_loop(name, unit(whir) + 0.4 * unit(low) + 0.05 * ring)

    # the shoji frames rattling in their track (the tell before they slam): light wooden ticks
    # coming faster, the paper buzzing in the frames, the frames sliding
    name = "sakura_shoji_rattle"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = np.zeros(n)
    tk = 0.02
    while tk < 0.72:
        g = 0.4 + 0.6 * tk / 0.72
        place(x, tk, wood_knock(r, 0.06, r.uniform(800, 1100), 0.012, 4000) +
              0.3 * taper(noise(r, ns(0.06), 250, 1800) * np.exp(-tv(0.06) / 0.008)), g * r.uniform(0.5, 1.0))
        tk += r.uniform(0.03, 0.065) * (1.0 - 0.4 * tk)
    slide = noise(r, n, 120, 900) * (0.3 + 0.7 * np.abs(noise(r, n, None, 25))) * np.sin(np.pi * np.clip(t / 0.76, 0, 1))
    save(name, space(r, unit(x) + 0.35 * slide, 0.6, 0.15, 150, 7000), fin=0.006, fout=0.08)

    # the shoji panels clapping shut: a wooden clap, the frames' modes, the paper drumming and a
    # puff of air, then two small bounces
    name = "sakura_shoji_slam"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = 0.8 * click(r, dur(name), 600, 6000, 0.003)
    x += 0.7 * modes(t, [(r.uniform(250, 275), 1.0, 0.05), (r.uniform(590, 640), 0.7, 0.03), (r.uniform(1050, 1150), 0.45, 0.02),
                         (r.uniform(1850, 1990), 0.25, 0.01)], r, 0.0, hard=4000)
    fm = r.uniform(115, 135)
    x += 0.5 * modes(t, [(fm, 1.0, 0.04), (fm * 1.59, 0.6, 0.03), (fm * 2.14, 0.4, 0.02), (fm * 2.65, 0.25, 0.015)], r)
    x += 0.4 * noise(r, n, 60, 300) * env(t, 0.002, 0.04)
    for t0, g in ((0.09, 0.25), (0.15, 0.12)):
        place(x, t0, wood_knock(r, 0.1, r.uniform(600, 700), 0.015), g)
    save(name, space(r, x, 0.8, 0.25, 120, 7000), fin=0.0005, fout=0.12)

    # the wind rising in the trees upwind (the gust's tell): a band climbing, the leaves
    # rustling harder, a breathy whistle through the bamboo and a low push under it
    name = "sakura_gust_rise"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    k = np.clip(t / 1.25, 0, 1)
    e = k ** 1.6 * np.exp(-np.maximum(t - 1.25, 0) / 0.12)
    wind = unit(svf(r.standard_normal(n), 250 * (1100 / 250) ** k, 1.1))
    leaves = np.zeros(n)
    grains(r, leaves, 500, 0.0, dur(name), 2000, 9000, 0.001, 0.004, 1.0)
    whistle = unit(svf(r.standard_normal(n), 650 + 350 * k + 40 * np.sin(TAU * 1.3 * t), 18.0)) * k ** 2
    low = noise(r, n, 40, 180)
    save(name, (wind + 0.35 * unit(leaves) * k + 0.25 * whistle + 0.3 * low) * e, fin=0.05, fout=0.2)

    # the gust front sweeping across: a soft whoosh to the pass, a flurry of leaves and petals,
    # a breath of whistle, the bamboo knocking and a low buffet
    name = "sakura_gust"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    tp = 0.45
    ge = np.where(t < tp, np.exp(-0.5 * ((t - tp) / 0.2) ** 2), np.exp(-0.5 * ((t - tp) / 0.35) ** 2))
    w = whoosh(r, dur(name), 220, 1300, 380, tp, 0.2, 1.1)
    flurry = np.zeros(n)
    grains(r, flurry, 700, 0.1, 1.2, 1800, 9000, 0.001, 0.004, 1.0)
    whistle = unit(svf(r.standard_normal(n), np.interp(t, [0, tp, dur(name)], [600, 1050, 700]), 14.0)) * ge ** 1.5
    knocks = np.zeros(n)
    for _ in range(4):
        place(knocks, r.uniform(0.35, 0.9), bamboo_knock(r, 0.2, r.uniform(420, 620), 2500), r.uniform(0.4, 1.0))
    low = noise(r, n, 40, 200) * ge
    save(name, w + 0.35 * unit(flurry) * ge + 0.2 * whistle + 0.12 * unit(knocks) + 0.3 * low, fin=0.02, fout=0.2)

    # the giant mallet straining at the top of its stroke (the tell, about a second before it
    # strikes): the heavy beam groaning, the rope bindings squeaking and the pawl clacking home
    name = "sakura_mallet_creak"
    r = rng(name)
    x = np.zeros(ns(dur(name)))
    place(x, 0.02, groan(r, 0.7, 120.0, 1.0, (16.0, 40.0)), 1.0)
    rope = creak(r, 0.45, lambda u: 90.0 + 60.0 * np.sin(np.pi * u), [(r.uniform(1100, 1250), 1.0, 0.006),
                                                                      (r.uniform(2400, 2700), 0.5, 0.004)])
    place(x, 0.2, rope * np.hanning(len(rope)), 0.18)
    place(x, 0.68, wood_knock(r, 0.12, r.uniform(380, 420), 0.025), 0.35)
    save(name, space(r, x, 0.8, 0.2, 120, 6000), fin=0.006, fout=0.1)

    # the battering ram drawn back (its tell): a quicker, higher timber creak as the ropes take
    # the weight, a hemp squeak and a hollow knock as it settles
    name = "sakura_ram_creak"
    r = rng(name)
    x = np.zeros(ns(dur(name)))
    place(x, 0.0, wood_knock(r, 0.12, r.uniform(300, 340), 0.03), 0.4)
    place(x, 0.04, groan(r, 0.55, 165.0, 1.0, (25.0, 60.0)), 0.9)
    rope = creak(r, 0.35, lambda u: 140.0 + 80.0 * u, [(r.uniform(1300, 1450), 1.0, 0.005), (r.uniform(2800, 3100), 0.45, 0.003)])
    place(x, 0.25, rope * np.hanning(len(rope)), 0.2)
    save(name, space(r, x, 0.7, 0.2, 120, 6000), fin=0.004, fout=0.1)

    # a stage banked: a bronze wind chime tumbling through D minor pentatonic (D6 F6 G6 A6 C7) and a
    # soft little temple bell on D5 under it
    name = "sakura_chime"
    r = rng(name)
    x = np.zeros(ns(dur(name)))
    place(x, 0.0, modes(tv(1.4), bell_modes(midi(74), 0.5), r, 0.0, hard=3000), 0.45)
    notes = [86, 89, 91, 93, 98, 96, 91, 89]
    t0 = 0.03
    for m in notes:
        g = r.uniform(0.35, 0.6)
        place(x, t0, modes(tv(1.0), bar_modes(midi(m), 0.6, damp=0.8), r, 0.002, hard=7000), g)
        place(x, t0, taper(click(r, 0.02, 3000, 9000, 0.0006)), 0.1 * g)
        t0 += r.uniform(0.06, 0.11)
    save(name, space(r, x, 1.4, 0.25, 300, 9000), fin=0.001, fout=0.3)

    # the finish fireworks: two shells lobbed from mortars (hollow "pon"s), whistling up, bursting
    # and their kamuro stars crackling and glittering down
    name = "sakura_fireworks"
    r = rng(name)
    x = firework_shell(r, dur(name), 0.0, 0.5, (900, 2400), 85.0, 200, 0.12, True)
    x += 0.8 * firework_shell(r, dur(name), 0.3, 0.55, (1000, 2800), 100.0, 180, 0.1, True)
    save(name, space(r, x, 1.8, 0.35, 100, 7000, predelay=0.03), fin=0.002, fout=0.3)

    # the great bell tolling from the valley at the finish: the deep D bell heard from far off (its
    # brightness gone in the air), a long valley reverb and its echo off the far peaks
    name = "sakura_finish_bell"
    r = rng(name)
    t = tv(dur(name))
    f = midi(50)
    b = modes(t, bell_modes(f, 1.6), r, 0.0, hard=1600) * (1.0 + 0.1 * np.sin(TAU * 1.3 * t))
    b += 0.5 * modes(t, [(f * 0.5 * 1.003, 0.6, 2.2), (f * 1.005, 0.5, 1.4)], r)
    b = band(b + 0.3 * thud(t, 100, 60, 0.02, 0.04), None, 2500)
    x = b.copy()
    place(x, 0.55, band(b, 120, 1500), 0.3)
    place(x, 1.15, band(b, 150, 1100), 0.12)
    save(name, space(r, x, 3.0, 0.45, 70, 3500, predelay=0.05), fin=0.002, fout=0.6)

    # wind through the bamboo and pines (scaled by the gust's strength): a soft, broad rush with
    # bands wandering, leaves rustling in waves, culms knocking and a faint breathy whistle
    name = "sakura_wind"
    r = rng(name)
    n = ns(dur(name))
    gust = 0.6 + 0.4 * crand(r, n, 5)
    bed = unit(tilt(cnoise(r, n, 120, 7000, 1), -3.0, circular=True)) * gust
    band1 = unit(csvf(r.standard_normal(n), 550 * 2.0 ** (0.8 * crand(r, n, 4)), 1.4)) * gust
    leaves = np.zeros(n)
    grains(r, leaves, 900, 0.0, dur(name), 2000, 9000, 0.001, 0.004, 1.0, wrap=True)
    leaves = unit(leaves) * (0.4 + 0.6 * (0.5 + 0.5 * crand(r, n, 7))) * gust
    whistle = unit(csvf(r.standard_normal(n), 820 * 2.0 ** (0.15 * crand(r, n, 3)), 16.0)) * (0.5 + 0.5 * clfo(n, 2, 0.7))
    knocks = np.zeros(n)
    for _ in range(3):
        cplace(knocks, r.uniform(0, dur(name)), bamboo_knock(r, 0.2, r.uniform(420, 620), 2500), r.uniform(0.5, 1.0))
    save_loop(name, bed + 0.5 * band1 + 0.3 * leaves + 0.12 * whistle + 0.1 * unit(knocks))

    # a mountain waterfall close by: a bright, rushing roar, the plunge thundering under it, water
    # splashing on the rocks, droplets and a fine spray
    name = "sakura_waterfall"
    r = rng(name)
    n = ns(dur(name))
    roar = water_roar(r, n, 90, 8000, -1.5, 0.2)
    plunge = cnoise(r, n, 40, 300) * (0.7 + 0.3 * crand(r, n, 12))
    splash = np.zeros(n)
    grains(r, splash, 700, 0.0, dur(name), 900, 6000, 0.001, 0.005, 1.0, wrap=True)
    drops = np.zeros(n)
    for _ in range(30):
        cplace(drops, r.uniform(0, dur(name)), bubble(r.uniform(500, 1500), 0.05, r.uniform(0.006, 0.012), 0.8),
               r.uniform(0.3, 1.0))
    spray = cnoise(r, n, 4000, 10000)
    save_loop(name, roar + 0.45 * plunge + 0.3 * unit(splash) + 0.15 * unit(drops) + 0.1 * spray)

    # the rope bridge swaying: one sway each way per loop - the hemp ropes creaking at each end of
    # the sway, the planks groaning, loose boards tapping, and a little wind through the gorge
    name = "sakura_bridge_creak"
    r = rng(name)
    n = ns(dur(name))
    x = np.zeros(n)
    for t0 in (0.25, 1.25):
        rope = creak(r, 0.5, lambda u: 40.0 + 70.0 * np.sin(np.pi * u),
                     [(r.uniform(650, 760), 1.0, 0.012), (r.uniform(1500, 1700), 0.6, 0.007), (r.uniform(2900, 3200), 0.3, 0.004)])
        cplace(x, t0, rope * np.sin(np.pi * np.linspace(0, 1, len(rope))), r.uniform(0.5, 0.7))
    for t0, f0 in ((0.6, 170.0), (1.55, 150.0)):
        cplace(x, t0, groan(r, 0.6, f0 * r.uniform(0.95, 1.05)), r.uniform(0.8, 1.0))
    for _ in range(5):
        cplace(x, r.uniform(0, dur(name)), wood_knock(r, 0.1, r.uniform(300, 650), 0.02), r.uniform(0.15, 0.35))
    air = cnoise(r, n, 200, 2000) * (0.7 + 0.3 * crand(r, n, 4))
    save_loop(name, unit(x) + 0.12 * air)


def gen_jungle():
    # a vine taking the swing at the end of its arc: the fibres stretching and the branch above
    # creaking, with a few leaves shaken loose
    name = "jungle_vine_creak"
    r = rng(name)
    x = np.zeros(ns(dur(name)))
    cr = creak(r, 0.5, lambda u: 30.0 + 45.0 * np.sin(np.pi * u),
               [(r.uniform(400, 450), 1.0, 0.012), (r.uniform(1000, 1150), 0.6, 0.008), (r.uniform(2200, 2400), 0.25, 0.004)])
    place(x, 0.04, cr * np.sin(np.pi * np.linspace(0, 1, len(cr))) ** 0.8, 0.8)
    place(x, 0.08, groan(r, 0.45, 200.0, 1.0, (20.0, 40.0)), 0.5)
    grains(r, x, 70, 0.05, 0.6, 2000, 8000, 0.001, 0.004, 0.06)
    save(name, space(r, x, 0.7, 0.15, 150, 6000, hf_damp=0.35), fin=0.004, fout=0.1)

    # the log raft bumping into something: a hollow log knock, a slap of water and a slosh
    name = "jungle_raft_bump"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = 0.7 * thud(t, 130, 70, 0.03, 0.06) + 0.5 * modes(t, [(r.uniform(200, 220), 1.0, 0.05), (r.uniform(470, 500), 0.6, 0.03),
                                                             (r.uniform(880, 940), 0.35, 0.015)], r, 0.0, hard=3000)
    x += 0.3 * click(r, dur(name), 400, 5000, 0.003)
    slap = noise(r, n, 300, 3000) * env(t, 0.002, 0.03) + unit(svf(r.standard_normal(n), glide(1500, 400, t, 0.15), 3.0)) * env(t, 0.005, 0.08)
    place(x, 0.015, slap, 0.5)
    for _ in range(5):
        place(x, r.uniform(0.05, 0.35), bubble(r.uniform(250, 600), 0.1, 0.018, 0.7), r.uniform(0.08, 0.2))
    x += 0.25 * noise(r, n, 150, 900) * env(t, 0.05, 0.15)
    save(name, x, fin=0.0008, fout=0.12)

    # the dart trap's mechanism clicking through its tell: a dry stone latch tick
    name = "jungle_dart_click"
    r = rng(name)
    t = tv(dur(name))
    x = 0.6 * click(r, dur(name), 1500, 8000, 0.0012)
    x += 0.6 * modes(t, [(r.uniform(1700, 1900), 1.0, 0.022), (r.uniform(2900, 3200), 0.5, 0.012), (r.uniform(4600, 5000), 0.2, 0.006)], r)
    x += 0.4 * thud(t, 260, 160, 0.01, 0.02, harm=(0.3, 0.1))
    save(name, x, fin=0.0005, fout=0.04)

    # the darts spat out of the wall: a ragged row of blowpipe "fft"s, each dart whizzing across
    # and a few thocking into the far side
    name = "jungle_dart_volley"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = np.zeros(n)
    for j in range(6):
        t0 = 0.01 + j * 0.022 + r.uniform(0, 0.012)
        tt = tv(0.3)
        puff = noise(r, len(tt), 500, 4000) * env(tt, 0.001, 0.012) + 0.6 * bubble(r.uniform(180, 240), 0.3, 0.01, 0.5)
        zip_ = unit(svf(r.standard_normal(len(tt)), glide(r.uniform(2000, 2600), r.uniform(4200, 5200), tt, 0.12), 5.0)) * \
            env(tt, 0.01, 0.06)
        place(x, t0, taper(puff + 0.5 * zip_), r.uniform(0.6, 1.0))
        if r.uniform() < 0.6:
            place(x, t0 + r.uniform(0.18, 0.26), wood_knock(r, 0.08, r.uniform(700, 1000), 0.012), r.uniform(0.15, 0.3))
    save(name, space(r, x, 0.9, 0.2, 200, 7000), fin=0.0005, fout=0.12)

    # a pressure plate pressed: a short stone scrape as it sinks, a solid clunk and the mechanism
    # below answering with a hollow click
    name = "jungle_plate_click"
    r = rng(name)
    t = tv(dur(name))
    x = np.zeros(len(t))
    sc = noise(r, ns(0.07), 300, 3000) * np.hanning(ns(0.07))
    place(x, 0.0, sc, 0.25)
    place(x, 0.06, thud(tv(0.25), 180, 90, 0.02, 0.035) + 0.5 * modes(tv(0.25), [(r.uniform(680, 760), 1.0, 0.02),
                                                                                (r.uniform(1250, 1400), 0.5, 0.01)], r) +
          0.5 * click(r, 0.25, 500, 6000, 0.002), 1.0)
    place(x, 0.17, wood_knock(r, 0.12, r.uniform(900, 1000), 0.02), 0.3)
    save(name, space(r, x, 0.9, 0.2, 150, 6000), fin=0.0008, fout=0.08)

    # the glyph gate grinding open: stone dragging up its slot, the counterweight chain rattling,
    # a deep rumble and dust, and a clunk as it locks at the top, in the temple
    name = "jungle_gate_open"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = np.zeros(n)
    grind = creak(r, 1.3, lambda u: 24.0 + 22.0 * np.sin(np.pi * u) ** 0.7,
                  [(r.uniform(100, 125), 1.0, 0.03), (r.uniform(240, 290), 0.7, 0.02), (r.uniform(520, 620), 0.45, 0.012),
                   (r.uniform(1100, 1300), 0.2, 0.006)])
    m = len(grind)
    rough = noise(r, m, 200, 2200) * (0.4 + 0.6 * np.abs(noise(r, m, None, 30)))
    place(x, 0.02, (grind + 0.4 * rough) * np.sin(np.pi * np.linspace(0, 1, m)) ** 0.4, 0.9)
    chain = np.zeros(n)
    for _ in range(50):
        place(chain, r.uniform(0.05, 1.25), modes(tv(0.08), bar_modes(r.uniform(1600, 2600), 0.02), r, 0.02, hard=6000),
              r.uniform(0.2, 1.0))
    x += 0.15 * unit(chain) + 0.35 * noise(r, n, 30, 200) * np.sin(np.pi * np.clip(t / 1.35, 0, 1))
    grains(r, x, 50, 0.1, 1.4, 1500, 6000, 0.001, 0.004, 0.08)
    place(x, 1.35, thud(tv(0.25), 120, 60, 0.03, 0.05, harm=(0.5, 0.2)) + 0.5 * click(r, 0.25, 400, 5000, 0.003), 0.8)
    save(name, space(r, x, 1.5, 0.3, 100, 6000), fin=0.01, fout=0.06)

    # the gate's countdown: a hollow wooden "tok" on A5, like a temple block
    name = "jungle_gate_tick"
    r = rng(name)
    t = tv(dur(name))
    f = midi(81)
    x = modes(t, [(f, 1.0, 0.045), (f * 2.62, 0.25, 0.012), (f * 3.93, 0.2, 0.008), (f * 0.5, 0.2, 0.02)], r, 0.0, hard=5000)
    x += 0.25 * click(r, dur(name), 1000, 7000, 0.001)
    save(name, space(r, x, 0.9, 0.15, 300, 8000), fin=0.0005, fout=0.06)

    # the gate dropping shut: a quick slide down its slot, a crushing stone thud with a crack, the
    # frame shuddering and dust and grit trickling, in the temple
    name = "jungle_gate_close"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = np.zeros(n)
    sl = noise(r, ns(0.26), 150, 1800) * np.linspace(0.2, 1.0, ns(0.26)) ** 2
    place(x, 0.0, taper(sl), 0.35)
    tt = tv(0.9)
    hit = 0.7 * thud(tt, 90, 45, 0.08, 0.14, harm=(0.5, 0.25)) + 0.7 * click(r, 0.9, 300, 7000, 0.005)
    hit += 0.65 * modes(tt, [(r.uniform(300, 340), 1.0, 0.03), (r.uniform(520, 580), 0.7, 0.02), (r.uniform(900, 1000), 0.4, 0.012)], r)
    hit += 0.5 * noise(r, len(tt), 50, 400) * env(tt, 0.003, 0.1)
    place(x, 0.26, hit, 1.0)
    grains(r, x, 70, 0.3, 1.1, 800, 5000, 0.002, 0.006, 0.12, decay=0.25)
    save(name, space(r, x, 1.4, 0.35, 90, 6000), fin=0.006, fout=0.2)

    # a trap's tell: a dry little tick of stone teeth, a touch brighter than the dart latch
    name = "jungle_trap_tick"
    r = rng(name)
    t = tv(dur(name))
    x = 0.5 * click(r, dur(name), 2000, 9000, 0.0008)
    x += 0.6 * modes(t, [(midi(88), 1.0, 0.03), (midi(88) * 2.4, 0.35, 0.014), (midi(88) * 3.9, 0.12, 0.007)], r)
    save(name, x, fin=0.0005, fout=0.04)

    # the boulder breaking loose: a crack of the niche, grit pouring, a deep rumble building as it
    # rocks forward, the stone groaning and its first knocks coming faster
    name = "jungle_boulder_rumble"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    k = np.clip(t / 1.7, 0, 1)
    x = 0.6 * click(r, dur(name), 400, 6000, 0.006)
    place(x, 0.0, thud(tv(0.4), 110, 55, 0.05, 0.08), 0.6)
    x += 0.9 * noise(r, n, 30, 260) * (0.15 + 0.85 * k ** 1.3) * (0.8 + 0.2 * np.sin(TAU * 5 * t))
    g = creak(r, 1.4, lambda u: 15.0 + 25.0 * u, [(r.uniform(85, 100), 1.0, 0.04), (r.uniform(210, 240), 0.6, 0.025),
                                                  (r.uniform(480, 540), 0.3, 0.012)])
    place(x, 0.25, g * np.sin(np.pi * np.linspace(0, 1, len(g))) ** 0.6, 0.35)
    gr = np.zeros(n)
    grains(r, gr, 220, 0.02, 1.9, 900, 5000, 0.001, 0.005, 1.0, decay=1.0)
    x += 0.25 * unit(gr)
    tk, gap = 0.6, 0.35
    while tk < dur(name) - 0.1:
        place(x, tk, thud(tv(0.2), r.uniform(110, 140), 55, 0.04, 0.05), 0.3 + 0.4 * tk / dur(name))
        tk += gap
        gap *= 0.8
    save(name, space(r, x, 1.4, 0.3, 80, 5000), fin=0.002, fout=0.3)

    # the boulder smashing: a huge thud and a crack, the ball bursting into rubble that tumbles and
    # rattles, splintered wood and leaves, and dust, in the temple
    name = "jungle_boulder_crash"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = 0.9 * thud(t, 90, 50, 0.15, 0.2, harm=(0.5, 0.25)) + 0.6 * click(r, dur(name), 500, 8000, 0.008)
    x += 0.7 * noise(r, n, 50, 450) * env(t, 0.003, 0.17)
    for _ in range(34):
        tj = 0.04 + r.gamma(1.5, 0.16)
        f0 = r.uniform(250, 1300)
        rock = modes(tv(0.12), [(f0, 1.0, 0.014), (f0 * 1.71, 0.6, 0.009), (f0 * 2.63, 0.4, 0.005)], r, 0.0)
        place(x, tj, rock + 0.5 * click(r, 0.12, f0 * 0.8, min(f0 * 7, 11000), 0.002), r.uniform(0.1, 0.4) * np.exp(-tj / 0.5))
    sp = np.zeros(n)
    grains(r, sp, 40, 0.02, 0.25, 1500, 7000, 0.0006, 0.002, 1.0)
    x += 0.2 * unit(sp)
    grains(r, x, 80, 0.05, 1.1, 1500, 7000, 0.001, 0.004, 0.12, decay=0.4)
    x += 0.12 * noise(r, n, 1000, 6000) * env(t, 0.05, 0.4)
    save(name, space(r, x, 1.4, 0.35, 90, 6000), fin=0.0008, fout=0.3)

    # the boulder plunging into the river: a deep "kerplunk" as it punches a cavity, the splash
    # bursting up, spray raining back, big bubbles glugging up and the wave slopping
    name = "jungle_boulder_splash"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = 0.8 * thud(t, 85, 45, 0.08, 0.12, harm=(0.4, 0.15))
    place(x, 0.02, bubble(70, 0.6, 0.12, 0.9), 0.7)
    x += 0.8 * unit(svf(r.standard_normal(n), glide(800, 2500, t, 0.1) * np.exp(-np.maximum(t - 0.1, 0) / 0.5), 0.9)) * \
        env(t, 0.008, 0.22)
    x += 0.4 * noise(r, n, 2000, 8000) * env(t, 0.02, 0.18)
    rain = np.zeros(n)
    grains(r, rain, 300, 0.25, 1.3, 1000, 6000, 0.001, 0.004, 1.0, decay=0.45)
    x += 0.3 * unit(rain)
    for _ in range(14):
        place(x, r.uniform(0.2, 1.1), bubble(r.uniform(120, 380), 0.25, r.uniform(0.03, 0.06), 0.7), r.uniform(0.15, 0.35))
    x += 0.4 * noise(r, n, 80, 600) * np.exp(-0.5 * ((t - 0.6) / 0.25) ** 2)
    save(name, space(r, x, 1.2, 0.25, 80, 6000), fin=0.0008, fout=0.3)

    # the altar waking at the finish: a slit drum calling up A minor (A3 C4 E4 A4), a deep stone
    # gong on A2 answering, a shimmer of wooden chimes and a breath of wind through the temple
    name = "jungle_altar"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = np.zeros(n)
    for j, m in enumerate((57, 60, 64, 69)):
        f = midi(m)
        tt = tv(0.6)
        drum = modes(tt, [(f, 1.0, 0.2), (f * 2.76, 0.22, 0.05), (f * 4.1, 0.08, 0.02)], r, 0.0, hard=2500)
        drum += 0.4 * thud(tt, f * 1.5, f, 0.01, 0.02) + 0.1 * click(r, 0.6, 400, 4000, 0.002)
        place(x, 0.02 + 0.16 * j, drum, 0.55 + 0.1 * j)
    f = midi(45)
    gong = modes(t, [(f, 1.0, 1.2), (f * 1.52, 0.6, 0.9), (f * 2.0, 0.5, 0.7), (f * 2.71, 0.35, 0.5), (f * 3.4, 0.2, 0.35),
                     (f * 4.3, 0.12, 0.25)], r, 0.004, hard=1800)
    place(x, 0.68, gong * np.minimum(t / 0.04, 1.0) + 0.5 * thud(t, 90, 50, 0.04, 0.06), 0.9)
    for j, m in enumerate((81, 84, 88, 91, 93, 88)):
        place(x, 0.75 + 0.09 * j + r.uniform(0, 0.03), wood_knock(r, 0.25, midi(m), 0.08, 7000), 0.12)
    x += 0.15 * unit(svf(r.standard_normal(n), 700 * 2.0 ** (0.5 * np.sin(TAU * 0.6 * t)), 1.5)) * \
        np.sin(np.pi * np.clip((t - 0.6) / 1.6, 0, 1)) ** 2
    save(name, space(r, x, 2.0, 0.35, 80, 6000, predelay=0.02), fin=0.002, fout=0.4)

    # the boulder rolling down the temple run: a heavy stone rumble, knocks from its chips coming
    # round twice a loop, grit crushed under it, leaves and twigs crunching and a little dust
    name = "jungle_boulder_roll"
    r = rng(name)
    n = ns(dur(name))
    rumble = cnoise(r, n, 35, 350) * (0.6 + 0.4 * crand(r, n, 14, 0.5))
    knocks = np.zeros(n)
    marks = [(r.uniform(0, 1.0), r.uniform(0.4, 1.0), r.uniform(95, 135)) for _ in range(6)]
    for rev in range(2):
        for ph, g, f in marks:
            tt = tv(0.2)
            k = thud(tt, f, 50, 0.04, 0.055) + 0.25 * band(click(r, 0.2, 300, 3500, 0.004), None, 3000)
            cplace(knocks, rev * 1.0 + ph, taper(k), g)
    grit = crackle(r, dur(name), 300, 700, 4500, wrap=True, n=n)
    leaves = np.zeros(n)
    grains(r, leaves, 260, 0.0, dur(name), 1800, 6000, 0.001, 0.004, 1.0, wrap=True)
    dust = cnoise(r, n, 1200, 4500)
    save_loop(name, unit(rumble) + 0.6 * unit(knocks) + 0.3 * unit(grit) + 0.2 * unit(leaves) + 0.1 * dust)

    # a big jungle waterfall (heard from a distance): a deep, heavy roar, the plunge pool
    # thundering, spray and a mist hiss, darker and bigger than the mountain falls
    name = "jungle_waterfall"
    r = rng(name)
    n = ns(dur(name))
    roar = water_roar(r, n, 50, 6000, -2.5, 0.25)
    thunder = cnoise(r, n, 30, 160) * (0.6 + 0.4 * crand(r, n, 10))
    splash = np.zeros(n)
    grains(r, splash, 500, 0.0, dur(name), 600, 4000, 0.002, 0.008, 1.0, wrap=True)
    mist = cnoise(r, n, 3000, 8000) * (0.8 + 0.2 * crand(r, n, 8))
    save_loop(name, roar + 0.55 * thunder + 0.25 * unit(splash) + 0.06 * mist)


def gen_neon():
    E2 = midi(40)
    # a hover car streaming past: the thrusters' electric drone (an E2 stack against a slightly
    # sharp copy, beating), a turbine whine on B5, the air it pushes
    name = "neon_car_hum"
    r = rng(name)
    n = ns(dur(name))
    i = np.arange(n) / SR
    a = hum_stack(n, cyc(E2, n), 14, 1.0, 1.2, r)
    b = hum_stack(n, cyc(E2, n) + 3.0, 10, 1.1, 1.0, r)
    whine = np.sin(TAU * cyc(midi(83), n) * i) + 0.35 * np.sin(TAU * cyc(midi(83) * 2, n) * i)
    air = cnoise(r, n, 300, 4000) * (0.7 + 0.3 * crand(r, n, 8))
    save_loop(name, unit(a + 0.7 * b) + 0.06 * whine + 0.3 * unit(air))

    # the searchlight drone's rotors: four props buzzing at slightly different rates (so they
    # beat), the chopped air, and the motors' whine
    name = "neon_drone_hum"
    r = rng(name)
    n = ns(dur(name))
    i = np.arange(n) / SR
    x = np.zeros(n)
    for f in (182.0, 186.0, 191.0, 195.0):
        x += np.roll(buzz_wave(cyc(f, n), n, 20, 1.3), int(r.integers(0, n)))   # stagger the saws' ramps
    chop = cnoise(r, n, 400, 4000) * (0.4 + 0.6 * (0.5 + 0.5 * clfo(n, 186)) ** 2)
    whine = np.sin(TAU * cyc(midi(88) * 2, n) * i) * (0.8 + 0.2 * clfo(n, 4))
    save_loop(name, unit(x) + 0.35 * unit(chop) + 0.04 * whine)

    # a hologram slab lit: the projector's soft electric hum, a shimmer of E-minor partials (E6 G6
    # B6) breathing in and out, and a faint fizz of static
    name = "neon_holo_hum"
    r = rng(name)
    n = ns(dur(name))
    i = np.arange(n) / SR
    hum = hum_stack(n, cyc(120.0, n), 8, 1.3, 1.3, r)
    sh = np.zeros(n)
    for m, cy in ((88, 3), (91, 5), (95, 4)):
        sh += np.sin(TAU * cyc(midi(m), n) * i) * (0.6 + 0.4 * clfo(n, cy, r.uniform(0, TAU)))
    fizz = crackle(r, dur(name), 40, 3000, 9000, wrap=True, n=n)
    air = cnoise(r, n, 1500, 7000)
    save_loop(name, 0.6 * hum + 0.25 * unit(sh) + 0.12 * unit(fizz) + 0.06 * air)

    # the gondola winch: an E3 motor hum, the gearbox whining, the cable ticking over the pulleys
    # and the cradle rumbling in its rails
    name = "neon_gondola_motor"
    r = rng(name)
    n = ns(dur(name))
    i = np.arange(n) / SR
    hum = hum_stack(n, cyc(midi(52), n), 12, 1.0, 1.4, r)
    gear = np.sin(TAU * cyc(midi(76) * 2, n) * i) * (0.7 + 0.3 * clfo(n, 12)) + 0.3 * np.sin(TAU * cyc(midi(83) * 2, n) * i)
    ticks = np.zeros(n)
    for k in range(12):
        cplace(ticks, k / 12.0 * dur(name), taper(modes(tv(0.04), bar_modes(r.uniform(1400, 1600), 0.01), r, 0.02) +
                                                  0.4 * click(r, 0.04, 1500, 6000, 0.001)), r.uniform(0.6, 1.0))
    rumble = cnoise(r, n, 50, 400) * (0.8 + 0.2 * crand(r, n, 6))
    save_loop(name, 0.6 * hum + 0.08 * gear + 0.3 * unit(ticks) + 0.4 * unit(rumble))

    # a rooftop vent: a soft steam hiss surging gently, a hollow throat, and the odd sputter
    name = "neon_steam_hiss"
    r = rng(name)
    n = ns(dur(name))
    hiss = unit(tilt(cnoise(r, n, 400, 9000, 1), -1.5, circular=True)) * (0.8 + 0.2 * crand(r, n, 6))
    throat = unit(csvf(r.standard_normal(n), 1600 * 2.0 ** (0.3 * crand(r, n, 3)), 4.0))
    low = cnoise(r, n, 80, 300) * (0.7 + 0.3 * crand(r, n, 5))
    sp = np.zeros(n)
    grains(r, sp, 20, 0.0, dur(name), 800, 4000, 0.003, 0.01, 1.0, wrap=True)
    save_loop(name, hiss + 0.25 * throat + 0.3 * low + 0.15 * unit(sp))

    # a big neon sign: the tubes' 120 Hz buzz (rich in harmonics, softened by the glass), the
    # ballast humming, a slight flicker and a spark now and then
    name = "neon_sign_buzz"
    r = rng(name)
    n = ns(dur(name))
    bz = buzz_wave(cyc(120.0, n), n, 30, 1.1, 0.6)
    bz = cband(bz, 100, 4500)
    ballast = hum_stack(n, cyc(60.0, n), 6, 1.2, 1.5, r)
    flick = 0.85 + 0.15 * crand(r, n, 12)
    sparks = crackle(r, dur(name), 6, 2000, 8000, wrap=True, n=n)
    save_loop(name, unit(bz) * flick + 0.4 * ballast + 0.25 * unit(sparks))

    # a hover car's horn, a second before it crosses: two quick blasts of a buzzy E4/G4 dyad through
    # a horn formant, climbing a touch as it closes in
    name = "neon_car_horn"
    r = rng(name)
    x = np.zeros(ns(dur(name)))
    for t0, d in ((0.0, 0.18), (0.26, 0.42)):
        tt = tv(d)
        m = len(tt)
        rise = 1.0 + 0.012 * (t0 + tt) / 0.7
        v = np.zeros(m)
        for mm, a in ((64, 1.0), (67, 0.8)):
            ph = TAU * np.cumsum(midi(mm) * rise) / SR
            for k in range(1, 14):
                v += a / k * np.sin(k * ph)
        v = unit(svf(v, 900.0, 1.6) + 0.5 * svf(v, 2400.0, 2.5))
        place(x, t0, v * np.minimum(tt / 0.012, 1.0) * np.minimum((d - tt) / 0.025, 1.0), 1.0)
    save(name, space(r, x, 1.0, 0.25, 200, 6000), fin=0.002, fout=0.12)

    # the drone setting off on a sweep: two synthetic blips climbing E6 -> B6, the rotors revving
    name = "neon_drone_chirp"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = np.zeros(n)
    for t0, f0, f1 in ((0.0, midi(88), midi(95)), (0.11, midi(91), midi(100))):
        tt = tv(0.09)
        f = glide(f0, f1, tt, 0.06)
        place(x, t0, taper((tone(f) + 0.25 * tone(2 * f)) * np.minimum(tt / 0.004, 1.0) * np.exp(-tt / 0.05)), 0.6)
    x += 0.4 * noise(r, n, 600, 4000) * (0.5 + 0.5 * np.sin(TAU * glide(60, 190, t, 0.3) * t)) ** 2 * env(t, 0.05, 0.12)
    save(name, x, fin=0.001, fout=0.06)

    # caught in the searchlight: a sharp electric zap, a crackle of sparks and a buzz falling from
    # E3 to E2 as the charge dumps
    name = "neon_drone_zap"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    f = glide(midi(52), midi(40), t, 0.35)
    ph = TAU * np.cumsum(f) / SR
    bz = np.zeros(n)
    for k in range(1, 20):
        bz += np.sin(k * ph) / k ** 0.9
    cr = crackle(r, 0.35, 120, 1500, 9000)
    z = np.zeros(n)
    place(z, 0.0, cr * np.exp(-tv(0.35) / 0.12), 1.0)
    x = 0.6 * band(unit(bz), None, 6000) * env(t, 0.003, 0.18) + 0.5 * unit(z)
    x += 0.5 * noise(r, n, 1500, 8000) * env(t, 0.001, 0.02) + 0.3 * noise(r, n, 2000, 7000) * env(t, 0.01, 0.12)
    save(name, x, fin=0.0005, fout=0.12)

    # a hologram starting to fail (the warning, about 0.9 s before it goes): static bursts
    # stuttering on and off, glitchy E-minor blips and the hum flickering, getting worse
    name = "neon_holo_glitch"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = np.zeros(n)
    hum = hum_stack(n, 120.0, 8, 1.3, 1.3)
    gate = np.zeros(n)
    tk = 0.0
    while tk < dur(name) - 0.04:
        on = r.uniform(0.015, 0.05)
        i0 = ns(tk)
        gate[i0:i0 + ns(on)] = 1.0
        tk += on + r.uniform(0.02, 0.09) * (1.0 - 0.6 * tk / dur(name))
    gate = band(gate, None, 300)
    stat = noise(r, n, 800, 7000)
    blips = np.zeros(n)
    for _ in range(9):
        m = int(r.choice([88, 91, 95, 98, 100]))
        tt = tv(r.uniform(0.02, 0.04))
        sq = np.sign(np.sin(TAU * midi(m) * tt)) * 0.5 + 0.5 * np.sin(TAU * midi(m) * tt)
        place(blips, r.uniform(0.05, 0.85), taper(band(sq, None, 6000) * np.minimum(tt / 0.002, 1.0), 0.003), r.uniform(0.3, 0.7))
    rise = 0.4 + 0.6 * t / dur(name)
    x = (0.5 * stat * gate + 0.25 * hum * (1.0 - 0.7 * gate) + 0.2 * unit(blips)) * rise
    x += 0.2 * unit(crackle(r, dur(name), 80, 2000, 9000)) * rise
    save(name, x, fin=0.004, fout=0.15)

    # the slab blinking out: a zip falling fast from 2 kHz, a soft pop and the hum cut off
    name = "neon_holo_off"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    f = 150.0 + 1850.0 * np.exp(-t / 0.035)
    x = (tone(f) + 0.3 * tone(2 * f)) * env(t, 0.002, 0.08)
    x += 0.5 * bubble(140, dur(name), 0.02, -0.3) + 0.3 * noise(r, n, 1000, 6000) * env(t, 0.001, 0.015)
    x += 0.15 * hum_stack(n, 120.0, 8, 1.3, 1.3) * np.exp(-t / 0.03)
    save(name, x, fin=0.0005, fout=0.08)

    # the slab snapping back into being: a quick rising zip, a shimmer of E6/G6/B6 settling and a
    # soft thump of the field taking
    name = "neon_holo_on"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    f = 200.0 * (1600.0 / 200.0) ** np.clip(t / 0.08, 0, 1)
    x = 0.6 * (tone(f) + 0.25 * tone(2 * f)) * np.minimum(t / 0.004, 1.0) * np.exp(-np.maximum(t - 0.08, 0) / 0.02)
    for m in (88, 91, 95):
        place(x, 0.07, tone(midi(m), tv(0.33)) * np.minimum(tv(0.33) / 0.01, 1.0) * np.exp(-tv(0.33) / 0.1), 0.25)
    place(x, 0.075, thud(tv(0.15), 140, 80, 0.02, 0.03), 0.4)
    save(name, x, fin=0.001, fout=0.08)

    # a checkpoint: an electric zap, an E-minor chime run (E6 G6 B6 E7, FM bells) and a burst of
    # sparks fizzing out, in the street
    name = "neon_checkpoint"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = 0.4 * noise(r, n, 1500, 8000) * env(t, 0.001, 0.015) + 0.3 * band(unit(buzz_wave(midi(40), n, 20, 1.0)), None, 5000) * env(t, 0.002, 0.05)
    for j, m in enumerate((88, 91, 95, 100)):
        tt = tv(0.7)
        f = midi(m)
        bell = np.sin(TAU * f * tt + 1.2 * np.exp(-tt / 0.08) * np.sin(TAU * f * 3.5 * tt)) * np.exp(-tt / 0.22)
        place(x, 0.04 + 0.07 * j, taper(bell * np.minimum(tt / 0.002, 1.0), 0.02), 0.45)
    sp = np.zeros(n)
    for _ in range(140):
        t0 = 0.02 + r.gamma(1.8, 0.12)
        if t0 < dur(name) - 0.02:
            place(sp, t0, noise(r, ns(0.004), 2500, 10000) * np.exp(-tv(0.004) / 0.0006), r.uniform(0.2, 1.0) ** 2)
    x += 0.35 * unit(sp)
    save(name, space(r, x, 1.2, 0.25, 200, 9000), fin=0.0008, fout=0.2)

    # the finish: fireworks bursting over the spire, crackling, and the city's sirens answering
    # from the streets below (two wails gliding between E5 and B5, softened by distance)
    name = "neon_finish"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = firework_shell(r, dur(name), 0.0, 0.45, (1300, 3400), 95.0, 240, 0.1)
    x += 0.8 * firework_shell(r, dur(name), 0.35, 0.5, (1100, 3000), 85.0, 200, 0.08)
    sir = np.zeros(n)
    for t0, rate, g in ((0.5, 0.9, 1.0), (0.75, 1.15, 0.7)):
        u = np.maximum(t - t0, 0)
        f = midi(76) * 2.0 ** ((7.0 / 12.0) * (0.5 - 0.5 * np.cos(TAU * rate * u)))
        ph = TAU * np.cumsum(f) / SR
        v = np.sin(ph) + 0.3 * np.sin(2 * ph) + 0.12 * np.sin(3 * ph)
        sir += g * v * np.clip(u / 0.4, 0, 1) * (t > t0)
    sir = band(sir, 300, 2500)
    x += 0.25 * unit(sir)
    save(name, space(r, x, 1.8, 0.35, 100, 7000, predelay=0.03), fin=0.002, fout=0.35)


def gen_frontier():
    # a lit fuse: a spitting hiss with a ragged edge, bright crackles and little pops of powder
    name = "frontier_fuse_hiss"
    r = rng(name)
    n = ns(dur(name))
    hiss = cnoise(r, n, 2500, 9000) * (0.6 + 0.4 * crand(r, n, 60, 0.3))
    body = cnoise(r, n, 600, 2500) * (0.5 + 0.5 * crand(r, n, 40, 0.3))
    cr = crackle(r, dur(name), 150, 2500, 9000, wrap=True, n=n)
    pops = np.zeros(n)
    for _ in range(8):
        cplace(pops, r.uniform(0, dur(name)), bubble(r.uniform(250, 500), 0.04, 0.006, 0.4) +
               0.5 * taper(noise(r, ns(0.04), 500, 4000) * np.exp(-tv(0.04) / 0.004)), r.uniform(0.4, 1.0))
    save_loop(name, unit(hiss) + 0.4 * unit(body) + 0.4 * unit(cr) + 0.3 * unit(pops))

    # the timber trestle collapsing (while it goes): a deep rumble, timbers groaning, planks and
    # chunks clattering down, dust, and the odd crack
    name = "frontier_collapse_rumble"
    r = rng(name)
    n = ns(dur(name))
    rumble = cnoise(r, n, 30, 250) * (0.6 + 0.4 * crand(r, n, 16, 0.5))
    wood = np.zeros(n)
    for t0, f0 in ((0.2, 120.0), (1.1, 95.0)):
        cplace(wood, t0, groan(r, 0.8, f0, 1.0, (14.0, 35.0)), r.uniform(0.6, 0.9))
    for t0 in (0.75, 1.7):
        cplace(wood, t0, taper(click(r, 0.15, 400, 8000, 0.004) + 0.5 * wood_knock(r, 0.15, r.uniform(180, 240), 0.03)), 0.7)
    deb = np.zeros(n)
    for _ in range(40):
        cplace(deb, r.uniform(0, dur(name)), wood_knock(r, 0.08, r.uniform(250, 1100), 0.015, 4000), r.uniform(0.2, 1.0))
    dust = cnoise(r, n, 1000, 5000) * (0.7 + 0.3 * crand(r, n, 6))
    save_loop(name, unit(rumble) + 0.45 * unit(wood) + 0.3 * unit(deb) + 0.1 * dust)

    # a steam jet: a high-pressure hiss surging gently, a whistling edge to it and the pipe's throat
    name = "frontier_steam_hiss"
    r = rng(name)
    n = ns(dur(name))
    hiss = unit(tilt(cnoise(r, n, 600, 10000, 1), -1.5, circular=True)) * (0.85 + 0.15 * crand(r, n, 8))
    edge = unit(csvf(r.standard_normal(n), 2200 * 2.0 ** (0.1 * crand(r, n, 3)), 8.0))
    throat = cnoise(r, n, 100, 500) * (0.8 + 0.2 * crand(r, n, 5))
    save_loop(name, hiss + 0.15 * edge + 0.3 * throat)

    # a mine cart running on the rails: iron wheels rumbling, the rail joints clacking under both
    # axles twice a loop, ore rattling in the bed and a faint wheel squeal
    name = "frontier_cart_rumble"
    r = rng(name)
    n = ns(dur(name))
    rumble = cnoise(r, n, 50, 500) * (0.7 + 0.3 * crand(r, n, 10))
    cl = np.zeros(n)
    for t0 in (0.05, 0.17, 0.55, 0.67):
        cplace(cl, t0, taper(thud(tv(0.08), 220, 140, 0.01, 0.015) + 0.5 * modes(tv(0.08), bar_modes(r.uniform(700, 820), 0.02), r, 0.02) +
                             0.3 * click(r, 0.08, 800, 5000, 0.001)), r.uniform(0.8, 1.0))
    ore = np.zeros(n)
    grains(r, ore, 160, 0.0, dur(name), 600, 3000, 0.002, 0.006, 1.0, wrap=True)
    squeal = unit(csvf(r.standard_normal(n), cyc(2800, n), 30.0)) * (0.5 + 0.5 * crand(r, n, 4)) ** 2
    save_loop(name, unit(rumble) + 0.55 * unit(cl) + 0.3 * unit(ore) + 0.05 * squeal)

    # the fuse catching: a match scratched along the box, the head flaring and the fuse spitting
    # into life
    name = "frontier_fuse_light"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = np.zeros(n)
    sc = noise(r, ns(0.07), 1000, 7000) * (0.3 + 0.7 * np.abs(noise(r, ns(0.07), None, 200))) * np.hanning(ns(0.07))
    place(x, 0.0, sc, 0.6)
    tt = tv(0.4)
    flare = noise(r, len(tt), 200, 3000) * env(tt, 0.01, 0.1) + 0.5 * noise(r, len(tt), 2000, 8000) * env(tt, 0.005, 0.05)
    place(x, 0.07, taper(flare), 0.9)
    cr = crackle(r, 0.35, 70, 2500, 9000)
    place(x, 0.12, cr * np.minimum(tv(0.35) / 0.1, 1.0), 0.6)
    place(x, 0.12, noise(r, ns(0.35), 2500, 9000) * np.minimum(tv(0.35) / 0.15, 1.0), 0.2)
    save(name, x, fin=0.002, fout=0.1)

    # the dynamite going off: a crack and a deep blast, a pressure wave, rock and splinters raining
    # down and the boom rolling round the canyon (two echoes)
    name = "frontier_dynamite_boom"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = 0.75 * thud(t, 80, 34, 0.15, 0.22, harm=(0.55, 0.25)) + 0.7 * band(click(r, dur(name), 300, 9000, 0.006), None, 8000)
    x += 0.95 * unit(tilt(r.standard_normal(n), -3.0)) * env(t, 0.002, 0.09)
    x += 0.5 * noise(r, n, 35, 300) * env(t, 0.02, 0.45)
    for _ in range(36):
        tj = 0.1 + r.gamma(1.6, 0.18)
        f0 = r.uniform(300, 1400)
        place(x, tj, modes(tv(0.1), [(f0, 1.0, 0.012), (f0 * 1.71, 0.5, 0.007), (f0 * 2.63, 0.3, 0.004)], r) +
              0.4 * click(r, 0.1, f0, min(f0 * 6, 9000), 0.002), r.uniform(0.05, 0.25) * np.exp(-tj / 0.6))
    dry = x.copy()
    place(x, 0.38, band(dry, 40, 900), 0.3)
    place(x, 0.85, band(dry, 40, 600), 0.15)
    save(name, space(r, x, 1.6, 0.3, 50, 5000, predelay=0.03), fin=0.0005, fout=0.4)

    # the crossing bell as the signal arm starts down: a bright gong bell on G5 struck five times
    name = "frontier_signal_bell"
    r = rng(name)
    x = np.zeros(ns(dur(name)))
    for k in range(5):
        tt = tv(0.6)
        place(x, k * 0.2, modes(tt, bell_modes(midi(79), 0.35), r, 0.001, hard=5000) + 0.15 * click(r, 0.6, 2000, 8000, 0.0008),
              1.0 if k % 2 == 0 else 0.85)
    save(name, space(r, x, 1.0, 0.2, 200, 8000), fin=0.0008, fout=0.35)

    # the signal arm locking level: an iron clank, the arm's bar ringing briefly and a rattle
    name = "frontier_signal_clank"
    r = rng(name)
    t = tv(dur(name))
    x = 0.6 * thud(t, 160, 90, 0.02, 0.04) + 0.6 * click(r, dur(name), 400, 7000, 0.003)
    x += 0.6 * modes(t, bar_modes(r.uniform(330, 380), 0.12), r, 0.02, hard=5000)
    for t0, g in ((0.07, 0.25), (0.12, 0.12)):
        place(x, t0, modes(tv(0.1), bar_modes(r.uniform(900, 1100), 0.02), r, 0.02) + 0.3 * click(r, 0.1, 800, 6000, 0.001), g)
    save(name, space(r, x, 0.8, 0.2, 150, 7000), fin=0.0005, fout=0.12)

    # the swinging signal arm clipping your boots: a short swish, a hard wooden thwack on the
    # painted arm with its iron strap ringing, and the arm juddering on its pivot
    name = "frontier_signal_thwack"
    r = rng(name)
    t = tv(dur(name))
    x = 0.35 * whoosh(r, dur(name), 300, 1600, 500, 0.035, 0.02, 1.3)
    hit = wood_knock(r, 0.4, r.uniform(280, 320), 0.035) + 0.6 * thud(tv(0.4), 170, 95, 0.015, 0.03)
    hit += 0.3 * modes(tv(0.4), bar_modes(r.uniform(560, 620), 0.08), r, 0.02, hard=5000) + 0.5 * click(r, 0.4, 600, 7000, 0.002)
    place(x, 0.035, hit, 1.0)
    for t0, g in ((0.11, 0.2), (0.17, 0.1)):
        place(x, t0, modes(tv(0.08), bar_modes(r.uniform(560, 620), 0.02), r, 0.02) + 0.3 * click(r, 0.08, 600, 5000, 0.001), g)
    save(name, space(r, x, 0.8, 0.2, 150, 7000), fin=0.002, fout=0.1)

    # a flat giving way: timbers splitting with a big crack, splinters spraying, fibres tearing,
    # the boards' modes and the drop
    name = "frontier_timber_crack"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = 0.8 * band(click(r, dur(name), 400, 9000, 0.004), None, 9000)
    x += 0.5 * modes(t, plate_modes(r.uniform(170, 200), 3.0, 0.05, 8, 0.7, r), r, 0.0, hard=3500)
    sp = np.zeros(n)
    grains(r, sp, 60, 0.0, 0.15, 1500, 7000, 0.0006, 0.003, 1.0)
    x += 0.35 * unit(sp)
    x += 0.3 * noise(r, n, 600, 3500) * (0.3 + 0.7 * np.abs(noise(r, n, None, 60))) * env(t, 0.01, 0.12)
    place(x, 0.32, thud(tv(0.4), 110, 55, 0.04, 0.07) + 0.4 * click(r, 0.4, 300, 4000, 0.004), 0.5)
    save(name, space(r, x, 1.2, 0.25, 80, 6000), fin=0.0005, fout=0.2)

    # the flats hauled back up on their chains: the chains rattling through, a winch pawl
    # clacking, the timbers creaking and a solid knock as they seat
    name = "frontier_collapse_rebuild"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = np.zeros(n)
    ch = np.zeros(n)
    for _ in range(90):
        place(ch, r.uniform(0.02, 1.15), modes(tv(0.08), bar_modes(r.uniform(1500, 2800), 0.02), r, 0.02, hard=7000), r.uniform(0.2, 1.0))
    x += 0.45 * unit(ch) * np.sin(np.pi * np.clip(t / 1.2, 0, 1)) ** 0.3
    for k in range(9):
        place(x, 0.05 + k * 0.13, modes(tv(0.05), bar_modes(r.uniform(1000, 1150), 0.012), r, 0.02) + 0.4 * click(r, 0.05, 800, 6000, 0.001), 0.3)
    g = groan(r, 1.0, 140.0, 1.0, (15.0, 35.0))
    place(x, 0.1, g, 0.35)
    place(x, 1.22, thud(tv(0.25), 130, 70, 0.03, 0.05) + 0.5 * wood_knock(r, 0.25, 220, 0.04), 0.7)
    save(name, space(r, x, 1.2, 0.25, 100, 6000), fin=0.006, fout=0.12)

    # the saloon doors swinging open: the spring hinge squealing up (stick-slip quickening into a
    # tone) and the leaves swishing
    name = "frontier_door_creak"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = np.zeros(n)
    cr = creak(r, 0.45, lambda u: 80.0 + 200.0 * np.sin(np.pi * u * 0.8), [(r.uniform(850, 950), 1.0, 0.01), (r.uniform(1800, 2000), 0.6, 0.006),
                                                                             (r.uniform(3000, 3300), 0.25, 0.003), (300, 0.4, 0.015)])
    place(x, 0.02, cr * np.sin(np.pi * np.linspace(0, 1, len(cr))) ** 0.6, 0.7)
    x += 0.35 * whoosh(r, dur(name), 200, 900, 300, 0.2, 0.1, 1.2)
    save(name, space(r, x, 0.8, 0.2, 150, 7000), fin=0.004, fout=0.1)

    # the saloon doors swinging shut: the two leaves clacking together, then bouncing smaller
    name = "frontier_door_clack"
    r = rng(name)
    x = np.zeros(ns(dur(name)))
    for t0, g in ((0.0, 1.0), (0.05, 0.8), (0.14, 0.35), (0.19, 0.25), (0.25, 0.1)):
        place(x, t0, wood_knock(r, 0.12, r.uniform(420, 520), 0.025), g)
    save(name, space(r, x, 0.8, 0.2, 150, 7000), fin=0.0005, fout=0.08)

    # the doors rattling before they shut: the leaves flapping against each other faster, and the
    # spring hinges chattering
    name = "frontier_door_rattle"
    r = rng(name)
    x = np.zeros(ns(dur(name)))
    tk, gap = 0.01, 0.075
    while tk < 0.42:
        place(x, tk, wood_knock(r, 0.06, r.uniform(500, 700), 0.015, 4000), r.uniform(0.5, 1.0))
        place(x, tk + 0.005, modes(tv(0.04), bar_modes(r.uniform(1900, 2300), 0.008), r, 0.02), 0.12)
        tk += gap * r.uniform(0.85, 1.15)
        gap *= 0.9
    save(name, space(r, x, 0.7, 0.15, 150, 7000), fin=0.0005, fout=0.08)

    # the doors slapping you out of the saloon: a fast swish and a hard wooden thwack, then the
    # leaves rattling back
    name = "frontier_door_slap"
    r = rng(name)
    t = tv(dur(name))
    x = 0.4 * whoosh(r, dur(name), 300, 1500, 400, 0.05, 0.03, 1.2)
    place(x, 0.06, 0.8 * thud(tv(0.3), 150, 80, 0.02, 0.04) + wood_knock(r, 0.3, r.uniform(330, 380), 0.04) +
          0.5 * click(r, 0.3, 500, 7000, 0.002), 1.0)
    for t0, g in ((0.16, 0.3), (0.24, 0.18), (0.3, 0.1)):
        place(x, t0, wood_knock(r, 0.1, r.uniform(450, 600), 0.02), g)
    save(name, space(r, x, 0.8, 0.2, 150, 7000), fin=0.001, fout=0.1)

    # the steam valve rattling and spitting before the jet fires: the valve chattering, short
    # spits of steam and a gurgle of condensate
    name = "frontier_steam_sputter"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = np.zeros(n)
    tk = 0.0
    while tk < 0.62:
        place(x, tk, modes(tv(0.04), bar_modes(r.uniform(1300, 1600), 0.01), r, 0.03) + 0.4 * click(r, 0.04, 1000, 6000, 0.001),
              r.uniform(0.15, 0.35))
        tk += r.uniform(0.025, 0.05)
    for t0 in r.uniform(0.02, 0.55, 5):
        d = r.uniform(0.04, 0.09)
        place(x, t0, noise(r, ns(d), 1000, 9000) * np.hanning(ns(d)), r.uniform(0.5, 1.0))
    for _ in range(6):
        place(x, r.uniform(0.05, 0.6), bubble(r.uniform(200, 500), 0.06, 0.012, 0.6), r.uniform(0.1, 0.25))
    save(name, x, fin=0.002, fout=0.08)

    # the steam jet firing: a thump of pressure and a burst of hiss that settles towards the jet
    name = "frontier_steam_burst"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = 0.6 * thud(t, 110, 60, 0.03, 0.05) + 0.4 * click(r, dur(name), 300, 4000, 0.004)
    x += noise(r, n, 600, 10000) * np.minimum(t / 0.01, 1.0) * (0.45 + 0.55 * np.exp(-t / 0.15))
    x += 0.3 * noise(r, n, 100, 600) * env(t, 0.005, 0.2)
    save(name, x, fin=0.001, fout=0.25)

    # the cart banging into the buffer: an iron clang, a heavy thud and the ore shifting in the bed
    name = "frontier_cart_clunk"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = 0.7 * thud(t, 120, 55, 0.03, 0.07, harm=(0.5, 0.2)) + 0.5 * click(r, dur(name), 400, 7000, 0.003)
    x += 0.5 * modes(t, plate_modes(r.uniform(250, 280), 1.4, 0.08, 10, 0.7, r), r, 0.0, hard=4000)
    ore = np.zeros(n)
    grains(r, ore, 70, 0.02, 0.4, 600, 3500, 0.002, 0.006, 1.0, decay=0.12)
    x += 0.35 * unit(ore)
    save(name, space(r, x, 1.0, 0.2, 100, 6000), fin=0.0005, fout=0.12)

    # the vault door opening: three bolts drawing back (each a slide and a ka-chunk), then the
    # heavy door groaning round on its hinges, in the bank
    name = "frontier_vault_open"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = np.zeros(n)
    for k in range(3):
        t0 = 0.02 + k * 0.17
        sl = noise(r, ns(0.06), 1500, 6000) * np.hanning(ns(0.06))
        place(x, t0, sl, 0.2)
        place(x, t0 + 0.06, modes(tv(0.15), bar_modes(r.uniform(700, 820), 0.05), r, 0.02, hard=5000) +
              0.5 * thud(tv(0.15), 200, 120, 0.01, 0.02) + 0.4 * click(r, 0.15, 800, 6000, 0.0015), 0.7)
    hinge = creak(r, 0.8, lambda u: 20.0 + 30.0 * np.sin(np.pi * u), [(r.uniform(140, 160), 1.0, 0.04), (r.uniform(380, 420), 0.7, 0.02),
                                                                    (r.uniform(900, 1000), 0.35, 0.01), (r.uniform(1900, 2100), 0.15, 0.005)])
    place(x, 0.55, hinge * np.sin(np.pi * np.linspace(0, 1, len(hinge))) ** 0.6, 0.7)
    x += 0.3 * noise(r, n, 40, 200) * np.sin(np.pi * np.clip((t - 0.55) / 0.8, 0, 1))
    save(name, space(r, x, 0.9, 0.25, 100, 6000), fin=0.002, fout=0.12)

    # the vault door slamming: a massive steel thud, the door's plate modes booming and ringing, and
    # the bolts snapping home
    name = "frontier_vault_slam"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = 0.9 * thud(t, 95, 40, 0.06, 0.12, harm=(0.5, 0.25)) + 0.6 * click(r, dur(name), 300, 7000, 0.004)
    x += 0.5 * modes(t, plate_modes(r.uniform(150, 170), 1.3, 0.25, 10, 0.6, r), r, 0.0, hard=3000)
    x += 0.3 * noise(r, n, 40, 300) * env(t, 0.003, 0.08)
    for t0 in (0.13, 0.21):
        place(x, t0, modes(tv(0.15), bar_modes(r.uniform(700, 820), 0.05), r, 0.02, hard=5000) + 0.4 * click(r, 0.15, 800, 6000, 0.0015), 0.4)
    save(name, space(r, x, 1.0, 0.3, 80, 6000), fin=0.0005, fout=0.2)

    # a stage of the heist banked: silver coins spilling into a pile and a little till bell on G6
    name = "frontier_coins"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = np.zeros(n)
    for _ in range(34):
        t0 = 0.01 + r.gamma(1.6, 0.09)
        if t0 < 0.6:
            place(x, t0, coin_hit(r, 0.3, r.uniform(1900, 3200)), r.uniform(0.25, 1.0) * np.exp(-t0 / 0.4))
    place(x, 0.02, thud(tv(0.2), 180, 110, 0.02, 0.03) + 0.4 * click(r, 0.2, 600, 4000, 0.003), 0.3)
    place(x, 0.0, modes(tv(0.8), bell_modes(midi(91), 0.3), r, 0.0, hard=6000), 0.3)
    save(name, space(r, x, 0.9, 0.15, 300, 9000), fin=0.0005, fout=0.15)

    # the locomotive whistle: a three-chime steam whistle on G major (G4 B4 D5) blown long and
    # loud, scooping into pitch, breathy with steam, echoing off the canyon walls
    name = "frontier_whistle"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    d = 1.45
    tt = tv(d)
    m = len(tt)
    scoop = 1.0 - 0.04 * np.exp(-tt / 0.06) - 0.012 * np.clip((tt - (d - 0.2)) / 0.2, 0, 1)
    e = np.minimum(tt / 0.06, 1.0) * np.minimum((d - tt) / 0.15, 1.0)
    v = np.zeros(m)
    for mm, a in ((67, 1.0), (71, 0.85), (74, 0.7)):
        f = midi(mm) * scoop * (1.0 + 0.002 * np.sin(TAU * 4.5 * tt + mm))
        ph = TAU * np.cumsum(f) / SR
        v += a * (np.sin(ph) + 0.35 * np.sin(2 * ph) + 0.15 * np.sin(3 * ph))
    steam = unit(svf(r.standard_normal(m), midi(71), 6.0))
    w = (unit(v) + 0.3 * steam + 0.15 * noise(r, m, 1500, 8000)) * e
    x = np.zeros(n)
    place(x, 0.0, w, 1.0)
    place(x, 0.42, band(w, 200, 2500), 0.22)
    save(name, space(r, x, 1.6, 0.3, 120, 6000, predelay=0.03), fin=0.004, fout=0.3)

    # the finish fireworks over the cab: a rocket and its burst, then a string of firecrackers
    # popping and a second, smaller rocket
    name = "frontier_fireworks"
    r = rng(name)
    x = firework_shell(r, dur(name), 0.0, 0.45, (1100, 2900), 95.0, 200, 0.06)
    x += 0.6 * firework_shell(r, dur(name), 0.55, 0.4, (1300, 3200), 110.0, 120, 0.0)
    tk = 0.6
    while tk < 1.45:
        tt = tv(0.08)
        pop = noise(r, len(tt), 300, 7000) * env(tt, 0.0005, 0.008) + 0.5 * thud(tt, 260, 140, 0.01, 0.01)
        place(x, tk, taper(pop), r.uniform(0.35, 0.6))
        tk += r.uniform(0.04, 0.09)
    save(name, space(r, x, 1.6, 0.3, 100, 7000, predelay=0.03), fin=0.002, fout=0.3)


# ===========================================================================
# the fourth set of new worlds (the very hard maps): Doom Fortress, The Abyss, Tempest Tower, The Void
# ===========================================================================
def uw(x, hi=3200.0, order=2):
    """Under water the high end soaks away fast: a gentle low-pass."""
    return band(x, None, hi, order)


def fm_glass(f, secs, tau, index=1.0, ratio=2.76, attack=0.003):
    """Struck glass / crystal: FM on an inharmonic ratio whose brightness dies away first."""
    t = tv(secs)
    x = np.sin(TAU * f * t + index * np.exp(-t / (tau * 0.3)) * np.sin(TAU * f * ratio * t))
    return taper(x * np.exp(-t / tau) * np.minimum(t / attack, 1.0), 0.01)


def voice(f, n, harmonics=20, tilt_pow=1.3, vib=0.004, vib_rate=5.0, r=None):
    """A sustained buzzy source (reed, horn, choir) following a pitch curve `f` (scalar or array)."""
    f = np.broadcast_to(np.asarray(f, dtype=float), (n,))
    t = np.arange(n) / SR
    ff = f * (1.0 + vib * np.sin(TAU * vib_rate * t + (r.uniform(0, TAU) if r is not None else 0.0)))
    ph = TAU * np.cumsum(ff) / SR
    x = np.zeros(n)
    top = float(np.max(f))
    for k in range(1, harmonics + 1):
        if top * k > SR * 0.42:
            break
        x += np.sin(k * ph) / k ** tilt_pow
    return unit(x)


def horn(r, secs, notes, form=(700.0, 1800.0), scoop=0.03, attack=0.03, release=0.08, harmonics=24):
    """A blown horn on one or more notes (midi): buzzy reeds through two formants, scooping into pitch."""
    t = tv(secs)
    n = len(t)
    v = np.zeros(n)
    for m in notes:
        v += voice(midi(m) * (1.0 - scoop * np.exp(-t / 0.06)), n, harmonics, 1.0, 0.002, 5.5, r)
    v = unit(svf(v, form[0], 1.6) + 0.5 * svf(v, form[1], 2.5))
    return taper(v * np.minimum(t / attack, 1.0) * np.clip((secs - t) / release, 0.0, 1.0))


def circ_creak(r, n, rate, spec):
    """creak() for a loop: a jittered stick-slip train run circularly through the resonances."""
    imp = np.zeros(n)
    d = n / SR
    pos = 0.0
    while pos < d - 1e-4:
        imp[int(pos * SR) % n] = r.uniform(0.5, 1.0)
        pos += 1.0 / max(rate(pos / d), 1.0) * r.uniform(0.85, 1.15)
    return unit(cconv(imp, modes(tv(0.08), spec)))


def thunder(r, secs, t0=0.0, size=1.0, f_hi=1500.0):
    """Thunder from a way off: no crack, a few rolls of low rumble tearing across the sky, each softer."""
    x = np.zeros(ns(secs))
    tk, g = t0, 1.0
    while tk < secs - 0.2:
        tt = tv(secs - tk)
        m = len(tt)
        roll = noise(r, m, 25, 260) * env(tt, r.uniform(0.04, 0.12), r.uniform(0.25, 0.5) * size)
        tear = noise(r, m, 200, f_hi) * env(tt, 0.01, 0.09 * size) * (0.4 + 0.6 * np.abs(noise(r, m, None, 30)))
        place(x, tk, taper(roll + 0.35 * tear, 0.05), g)
        tk += r.uniform(0.25, 0.55)
        g *= r.uniform(0.6, 0.85)
    return x


def iron_creak(r, secs, f0, rate=(20.0, 50.0)):
    """Steel under strain: a stick-slip groan through a beam's stiff, ringing resonances."""
    lo, hi = rate
    g = creak(r, secs, lambda u: lo + (hi - lo) * np.sin(np.pi * u) ** 1.2,
              [(f0, 1.0, 0.04), (f0 * 2.3, 0.7, 0.03), (f0 * 4.7, 0.45, 0.02), (f0 * 8.8, 0.25, 0.012),
               (f0 * 15.3, 0.12, 0.008)])
    return taper(g * np.sin(np.pi * np.linspace(0, 1, len(g))) ** 0.7, 0.02)


def sparks(r, secs, count, t_lo=0.0, t_hi=None, lo=2000, hi=7000, decay=None):
    """Sparks spitting: soft-edged ticks (kept below 7 kHz so a shower never turns harsh)."""
    buf = np.zeros(ns(secs))
    t_hi = secs if t_hi is None else t_hi
    for _ in range(count):
        t0 = r.uniform(t_lo, t_hi)
        a = r.uniform(0.2, 1.0) ** 2 * (np.exp(-(t0 - t_lo) / decay) if decay else 1.0)
        place(buf, t0, noise(r, ns(0.005), lo, hi) * np.exp(-tv(0.005) / r.uniform(0.0004, 0.0012)), a)
    return buf


# ---------------------------------------------------------------------------
# The Abyss (score in D minor): everything heard through water - low-passed, bubbly, slow.
# ---------------------------------------------------------------------------
def gen_abyss():
    # a glow cap starting to fail: a falling, wavering glassy chime (A6 F6 D6 A5, sagging and
    # flickering), a fizz of spores shed into the water and a few bubbles
    name = "abyss_lamp_dim"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = np.zeros(n)
    for j, m in enumerate((93, 89, 86, 81)):
        tt = tv(0.7)
        f = midi(m) * 2.0 ** (-0.5 / 12.0 * tt / 0.7) * (1.0 + 0.006 * np.sin(TAU * (5.5 + j) * tt))
        ph = TAU * np.cumsum(f) / SR
        v = (np.sin(ph + 0.8 * np.exp(-tt / 0.05) * np.sin(2.76 * ph)) + 0.2 * np.sin(2 * ph)) * np.exp(-tt / 0.22)
        v *= np.minimum(tt / 0.004, 1.0) * (0.75 + 0.25 * np.sin(TAU * (9.0 + 2.0 * j) * tt))
        place(x, 0.17 * j, taper(v, 0.02), 0.5 * (1.0 - 0.12 * j))
    sp = np.zeros(n)
    grains(r, sp, 40, 0.05, 0.9, 2500, 6000, 0.001, 0.004, 1.0, decay=0.5)
    b = np.zeros(n)
    for _ in range(6):
        place(b, r.uniform(0.1, 0.8), bubble(r.uniform(500, 1100), 0.06, r.uniform(0.008, 0.016)), r.uniform(0.3, 0.8))
    x = unit(x) + 0.12 * unit(sp) + 0.2 * unit(b)
    save(name, space(r, uw(x, 6000), 1.4, 0.3, 200, 5000), fin=0.002, fout=0.15)

    # the light going out: a muffled pop (a bubble collapsing downwards), a soft thump, a little
    # glassy blip falling away and the water settling
    name = "abyss_lamp_out"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = 0.8 * bubble(170, dur(name), 0.05, -0.4) + 0.5 * thud(t, 140, 70, 0.03, 0.05)
    x += 0.3 * noise(r, n, 200, 1500) * env(t, 0.001, 0.02)
    fb = 300.0 + 900.0 * np.exp(-t / 0.05)
    x += 0.15 * tone(fb) * env(t, 0.001, 0.05)
    for _ in range(5):
        place(x, r.uniform(0.04, 0.3), bubble(r.uniform(350, 800), 0.05, r.uniform(0.008, 0.015)), r.uniform(0.1, 0.25))
    save(name, space(r, uw(x, 3000), 0.9, 0.2, 150, 3000), fin=0.0008, fout=0.12)

    # the cap lighting up again: a soft burble of bubbles climbing in pitch and a D-minor shimmer
    # (D5 F5 A5 D6) blooming out of it
    name = "abyss_lamp_on"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    b = np.zeros(n)
    for k in range(14):
        t0 = 0.25 * k / 14.0 + r.uniform(0, 0.015)
        place(b, t0, bubble(300 * 2.0 ** (1.6 * k / 14.0) * r.uniform(0.9, 1.1), 0.06, r.uniform(0.008, 0.018)),
              r.uniform(0.5, 1.0))
    sh = np.zeros(n)
    for j, m in enumerate((74, 77, 81, 86)):
        tt = tv(0.5)
        v = fm_glass(midi(m), 0.5, 0.25, 0.5, 2.76, 0.06)
        place(sh, 0.12 + 0.03 * j, v, 0.6)
    x = 0.6 * unit(b) + 0.5 * unit(sh)
    save(name, space(r, uw(x, 6000), 1.2, 0.3, 200, 5000), fin=0.002, fout=0.12)

    # a vent getting ready to erupt: a low gurgling rumble swelling under the floor, gulps of gas
    # coming faster and grit rattling in the throat
    name = "abyss_vent_rumble"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    swell = np.minimum(t / 0.9, 1.0) ** 1.4
    x = noise(r, n, 20, 140) * (0.6 + 0.4 * np.abs(noise(r, n, None, 12))) * swell
    g = np.zeros(n)
    for _ in range(24):
        t0 = 0.95 * r.uniform(0, 1) ** 0.5
        place(g, t0, bubble(r.uniform(110, 380), 0.12, r.uniform(0.02, 0.04), 0.4), r.uniform(0.4, 1.0))
    grains(r, g, 18, 0.3, 0.95, 500, 1800, 0.002, 0.006, 0.15)
    x = unit(x) + 0.5 * unit(g) * swell
    save(name, uw(x, 2500, 3), fin=0.03, fout=0.05)

    # the vent erupting: a deep whump, a roar of gas and a cloud of bubbles bursting up and away
    name = "abyss_vent_burst"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = 0.9 * thud(t, 75, 35, 0.12, 0.15) + noise(r, n, 30, 600) * env(t, 0.01, 0.3)
    b = np.zeros(n)
    for _ in range(90):
        t0 = 0.01 + r.gamma(1.5, 0.15)
        if t0 < dur(name) - 0.05:
            place(b, t0, bubble(r.uniform(250, 1800), 0.07, r.uniform(0.006, 0.025)), r.uniform(0.2, 1.0) * np.exp(-t0 / 0.5))
    x += 0.7 * unit(b) + 0.25 * noise(r, n, 600, 2500) * env(t, 0.02, 0.25)
    save(name, space(r, uw(x, 4000, 3), 1.2, 0.2, 80, 3000), fin=0.002, fout=0.25)

    # the angler about to strike: a deep, wet, uneven growl swelling up out of its throat, the lure's
    # stalk creaking as it is snatched back, and a gurgle
    name = "abyss_angler_growl"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    imp = np.zeros(n)
    pos = 0.0
    while pos < dur(name):
        imp[min(int(pos * SR), n - 1)] = r.uniform(0.6, 1.0)
        pos += 1.0 / (44.0 + 10.0 * np.sin(TAU * 1.3 * pos) + r.uniform(-6.0, 6.0))
    body = fconv(imp, modes(tv(0.06), [(170, 1.0, 0.025), (390, 0.6, 0.014), (820, 0.3, 0.007), (1500, 0.12, 0.004)]))[:n]
    body = unit(body) * (0.6 + 0.4 * np.abs(noise(r, n, None, 25))) * np.minimum(t / 0.55, 1.0) ** 1.3
    x = body + 0.3 * noise(r, n, 30, 160) * np.minimum(t / 0.5, 1.0)
    place(x, 0.02, iron_creak(r, 0.45, 520, (25.0, 70.0)) * 0.6, 0.35)
    for _ in range(10):
        place(x, r.uniform(0.2, 0.9), bubble(r.uniform(180, 500), 0.08, r.uniform(0.015, 0.03), 0.3), r.uniform(0.1, 0.3))
    save(name, space(r, band(x, 40, 2500), 1.2, 0.25, 100, 2500), fin=0.01, fout=0.1)

    # the jaw slamming shut: the water shoved aside, a massive bony clap, teeth crunching together,
    # a slosh and the bubbles it knocked loose
    name = "abyss_angler_snap"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = np.zeros(n)
    place(x, 0.0, whoosh(r, 0.22, 200, 900, 300, 0.12, 0.04), 0.4)
    tt = tv(0.6)
    place(x, 0.14, thud(tt, 110, 45, 0.06, 0.12, harm=(0.45, 0.2)) + 0.6 * click(r, 0.6, 300, 3500, 0.006), 1.0)
    cr = np.zeros(n)
    for _ in range(14):
        f0 = r.uniform(900, 2400)
        place(cr, 0.14 + r.gamma(1.2, 0.012),
              modes(tv(0.03), [(f0, 1.0, r.uniform(0.004, 0.01)), (f0 * 1.9, 0.5, 0.004)], r) +
              0.4 * click(r, 0.03, 800, 4000, 0.001), r.uniform(0.3, 1.0))
    x += 0.5 * unit(cr)
    place(x, 0.15, noise(r, ns(0.5), 80, 700) * env(tv(0.5), 0.005, 0.15), 0.4)
    for _ in range(30):
        t0 = 0.16 + r.gamma(1.4, 0.08)
        if t0 < 0.75:
            place(x, t0, bubble(r.uniform(300, 1400), 0.05, r.uniform(0.006, 0.02)), r.uniform(0.05, 0.25))
    save(name, space(r, uw(x, 3500), 1.0, 0.2, 100, 3000), fin=0.001, fout=0.15)

    # a sunken anchor's warning: its chain and iron stock groaning under the water, links clinking
    # as the slack is taken up, and a deep stir of the water
    name = "abyss_anchor_creak"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = np.zeros(n)
    place(x, 0.0, iron_creak(r, 0.9, 150, (18.0, 42.0)), 1.0)
    ch = np.zeros(n)
    for k in range(7):
        place(ch, 0.1 + 0.11 * k + r.uniform(-0.02, 0.02),
              modes(tv(0.12), bar_modes(r.uniform(900, 1300), 0.035), r, 0.02, hard=3000), r.uniform(0.5, 1.0))
    x = unit(x) + 0.3 * unit(ch) + 0.25 * noise(r, n, 40, 200) * np.sin(np.pi * t / dur(name))
    save(name, space(r, uw(x, 3000), 1.5, 0.3, 100, 3000), fin=0.01, fout=0.15)

    # a mantis shrimp cocking its club: two dry clicks, then the snap - a hard knock and the
    # cavitation bubble collapsing with a pop - and a fizz of tiny bubbles
    name = "abyss_shrimp_click"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = np.zeros(n)
    for t0, g in ((0.0, 0.4), (0.12, 0.5)):
        place(x, t0, click(r, 0.03, 900, 3500, 0.0012) + 0.6 * modes(tv(0.03), [(1900, 1.0, 0.006), (3100, 0.4, 0.004)], r), g)
    tt = tv(0.3)
    snap = click(r, 0.3, 700, 5000, 0.0025) + 0.6 * bubble(650, 0.3, 0.012, -0.5) + 0.5 * thud(tt, 230, 110, 0.02, 0.03)
    place(x, 0.24, snap, 1.0)
    for _ in range(25):
        place(x, r.uniform(0.25, 0.5), bubble(r.uniform(1400, 3500), 0.02, r.uniform(0.002, 0.005)), r.uniform(0.05, 0.2))
    save(name, space(r, band(x, 150, 5000), 0.8, 0.15, 200, 4000), fin=0.0005, fout=0.12)

    # the leviathan upstream: a vast, low moan (a harmonic voice gliding A1 -> D2 -> A1 through a
    # slowly opening formant), heard through a great deal of water and dark
    name = "abyss_leviathan_moan"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    u = np.clip(t / 2.3, 0.0, 1.0)
    f = midi(33) * 2.0 ** (5.0 / 12.0 * np.sin(np.pi * u) ** 1.3) * (1.0 + 0.004 * np.sin(TAU * 3.2 * t))
    v = voice(f, n, 40, 1.05, 0.0, 1.0)
    form = svf(v, 260.0 * 2.0 ** (1.2 * np.sin(np.pi * u)), 2.5)
    e = np.minimum(t / 0.6, 1.0) ** 1.5 * np.clip((dur(name) - t) / 0.7, 0.0, 1.0)
    x = (0.6 * unit(band(v, None, 900)) + 0.7 * unit(form)) * e
    x += 0.15 * noise(r, n, 40, 300) * e
    save(name, space(r, band(x, 30, 1500), 2.8, 0.45, 60, 1800, predelay=0.05), fin=0.02, fout=0.3)

    # the surge front breaking over the stage: a huge underwater whoosh, a thump of pressure and a
    # swarm of bubbles torn along with it
    name = "abyss_surge_whoosh"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = whoosh(r, dur(name), 80, 700, 150, 0.35, 0.18, q=1.2) + 0.6 * noise(r, n, 30, 400) * env(t, 0.25, 0.5)
    place(x, 0.28, thud(tv(0.6), 70, 38, 0.1, 0.2), 0.6)
    b = np.zeros(n)
    for _ in range(120):
        t0 = 0.1 + r.gamma(2.5, 0.12)
        if t0 < dur(name) - 0.05:
            place(b, t0, bubble(r.uniform(250, 1500), 0.06, r.uniform(0.006, 0.02)), r.uniform(0.2, 1.0))
    x += 0.35 * unit(b)
    save(name, space(r, uw(x, 3000), 1.6, 0.3, 60, 2500), fin=0.01, fout=0.3)

    # a checkpoint: a bright glassy bloom (D6 F6 A6 D7 over a soft D5/A5 swell) and a rush of
    # bubbles rising past
    name = "abyss_checkpoint"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    b = np.zeros(n)
    for k in range(60):
        t0 = 0.5 * (k / 60.0) ** 0.8 + r.uniform(0, 0.02)
        place(b, t0, bubble(300 * 2.0 ** (2.5 * k / 60.0) * r.uniform(0.85, 1.15), 0.06, r.uniform(0.006, 0.02)),
              r.uniform(0.3, 1.0))
    gl = np.zeros(n)
    for j, m in enumerate((86, 89, 93, 98)):
        place(gl, 0.05 + 0.06 * j, fm_glass(midi(m), 0.9, 0.35, 1.0), 0.6)
    pad = (tone(midi(74), t) + 0.7 * tone(midi(81), t)) * env(t, 0.15, 0.4)
    x = 0.6 * unit(gl) + 0.4 * unit(b) + 0.15 * pad
    save(name, space(r, band(x, None, 7000), 1.6, 0.35, 200, 6000), fin=0.002, fout=0.25)

    # the finish: the submarine's horn booming through the deep (a reedy D2/A2 blast and its echo
    # off the trench walls) and a swell of shimmering light (D-minor partials) and rising bubbles
    name = "abyss_finish"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    hn = horn(r, 1.7, (38, 45), (380.0, 900.0), 0.04, 0.12, 0.4, 30)
    x = np.zeros(n)
    place(x, 0.0, hn, 1.0)
    place(x, 0.55, band(hn, None, 1200), 0.3)
    place(x, 1.15, band(hn, None, 800), 0.12)
    sw = np.zeros(n)
    for m, cy in ((86, 3.0), (89, 4.1), (93, 3.6), (98, 5.0)):
        sw += np.sin(TAU * midi(m) * t + r.uniform(0, TAU)) * (0.6 + 0.4 * np.sin(TAU * cy * t))
    sw *= np.clip((t - 0.3) / 1.4, 0.0, 1.0) ** 1.5 * np.clip((dur(name) - t) / 1.0, 0.0, 1.0)
    b = np.zeros(n)
    for _ in range(50):
        place(b, r.uniform(0.3, 2.6), bubble(r.uniform(400, 1600), 0.06, r.uniform(0.006, 0.02)), r.uniform(0.2, 1.0))
    x = unit(x) + 0.18 * unit(sw) + 0.15 * unit(b) + 0.04 * noise(r, n, 3000, 7000) * np.clip((t - 0.4) / 1.4, 0, 1)
    save(name, space(r, x, 2.5, 0.4, 60, 5000, predelay=0.04), fin=0.004, fout=0.45)

    # a current running (loop): a deep rush of moving water, a slow swirl, a soft hiss and bubbles
    # drifting with it
    name = "abyss_current_loop"
    r = rng(name)
    n = ns(dur(name))
    rush = water_roar(r, n, 40, 1800, -3.0, 0.35)
    swirl = unit(csvf(r.standard_normal(n), 300 * 2.0 ** (0.7 * crand(r, n, 5)), 2.0))
    hiss = cnoise(r, n, 800, 3000) * (0.5 + 0.5 * crand(r, n, 12))
    b = np.zeros(n)
    for _ in range(50):
        cplace(b, r.uniform(0, dur(name)), bubble(r.uniform(250, 1200), 0.06, r.uniform(0.008, 0.02)), r.uniform(0.2, 1.0))
    save_loop(name, cband(rush + 0.45 * swirl + 0.15 * hiss + 0.25 * unit(b), None, 3000, 3))

    # the leviathan's surge while it blows (loop): a heavier, lower roar of displaced water churning
    # and throbbing, with bubbles torn through it
    name = "abyss_surge_loop"
    r = rng(name)
    n = ns(dur(name))
    roar = water_roar(r, n, 25, 1200, -4.0, 0.3)
    churn = unit(csvf(r.standard_normal(n), 180 * 2.0 ** (0.9 * crand(r, n, 4)), 1.6))
    b = np.zeros(n)
    for _ in range(120):
        cplace(b, r.uniform(0, dur(name)), bubble(r.uniform(200, 1500), 0.06, r.uniform(0.006, 0.02)), r.uniform(0.2, 1.0))
    x = (roar + 0.6 * churn) * (0.8 + 0.2 * clfo(n, 3)) + 0.3 * unit(b)
    save_loop(name, cband(x, None, 2500, 3))


# ---------------------------------------------------------------------------
# Tempest Tower (score in B minor): wind, rain, steelwork, site machinery and lightning.
# ---------------------------------------------------------------------------
def gen_tempest():
    # the storm round the steelwork (loop): a broad roar gusting, two whistles through the frame
    # (near B4 and F#5) rising with the gusts, and rain hissing
    name = "tempest_wind"
    r = rng(name)
    n = ns(dur(name))
    gust = 0.6 + 0.4 * crand(r, n, 6)
    base = unit(tilt(cnoise(r, n, 80, 6000, 1), -3.0, circular=True))
    h1 = unit(csvf(r.standard_normal(n), midi(71) * 2.0 ** (0.25 * crand(r, n, 4)), 12.0))
    h2 = unit(csvf(r.standard_normal(n), midi(78) * 2.0 ** (0.2 * crand(r, n, 3)), 14.0))
    rain = cnoise(r, n, 2000, 8000)
    save_loop(name, cband(base * gust + 0.25 * h1 * gust ** 2 + 0.12 * h2 * gust + 0.1 * rain, 40, 7000))

    # a squall line racing in (the tell, 1.2 s ahead): a roar building, its band sweeping up, rain
    # thickening into a hiss, the frame whistling and loose scraps rattling as it arrives
    name = "tempest_gust_rise"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    e = np.where(t < 1.25, np.clip(t / 1.25, 0, 1) ** 2.2, np.exp(-(t - 1.25) / 0.15))
    roar = unit(tilt(noise(r, n, 60, 7000), -2.5))
    sw = unit(svf(r.standard_normal(n), glide(300, 1400, t, 1.25), 1.5))
    howl = unit(svf(r.standard_normal(n), glide(midi(71), midi(78), t, 1.25), 10.0))
    rain = noise(r, n, 2500, 8000)
    drops = np.zeros(n)
    for _ in range(60):
        place(drops, 1.3 * r.uniform(0, 1) ** 0.5, ga.grain(r, 0.01, 1500, 5000, 0.0015), r.uniform(0.2, 1.0))
    deb = np.zeros(n)
    for _ in range(10):
        place(deb, r.uniform(1.0, 1.3), wood_knock(r, 0.08, r.uniform(300, 900), 0.012, 4000), r.uniform(0.3, 1.0))
    x = (roar + 0.6 * sw + 0.2 * howl + 0.2 * rain * e ** 0.5) * e + 0.15 * unit(drops) + 0.25 * unit(deb)
    save(name, band(x, None, 8000), fin=0.05, fout=0.1)

    # the gust front slamming into the tower: a hard whoosh, the steel frame thumping and booming,
    # a tarp flapping wildly and rain spraying
    name = "tempest_gust"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = whoosh(r, dur(name), 150, 1500, 400, 0.08, 0.12, q=1.2)
    x += 0.7 * unit(tilt(noise(r, n, 50, 6000), -3.0)) * env(t, 0.02, 0.45)
    place(x, 0.05, thud(tv(0.5), 90, 60, 0.05, 0.12) + 0.4 * modes(tv(0.5), plate_modes(r.uniform(180, 220), 1.8, 0.15, 8, 0.7, r), r, 0.02, hard=2500), 0.5)
    tk = 0.1
    k = 0
    while tk < 0.95:
        place(x, tk, noise(r, ns(0.04), 300, 3000) * np.exp(-tv(0.04) / 0.01), 0.35 * np.exp(-tk / 0.5))
        tk += 0.045 + 0.02 * k / 6.0 + r.uniform(0, 0.02)
        k += 1
    x += 0.2 * noise(r, n, 2000, 8000) * env(t, 0.01, 0.3)
    save(name, band(x, None, 8000), fin=0.002, fout=0.25)

    # a lightning rod charging (the tell, 1.4 s ahead): a buzz climbing B2 -> B4 and trembling
    # faster, corona hissing and crackles crawling up the rod thicker and thicker
    name = "tempest_rod_charge"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    u = t / dur(name)
    f = midi(47) * 4.0 ** (u ** 1.5)
    ph = TAU * np.cumsum(f) / SR
    bz = np.zeros(n)
    for k in range(1, 17):
        bz += np.sin(k * ph) / k ** 1.2
    trem = 0.7 + 0.3 * np.sin(TAU * np.cumsum(8.0 + 22.0 * u) / SR)
    bz = band(unit(bz), None, 5000) * (0.1 + 0.9 * u ** 1.5) * trem
    cr = np.zeros(n)
    for _ in range(170):
        t0 = dur(name) * r.uniform(0, 1) ** 0.5
        place(cr, t0, noise(r, ns(0.005), 2000, 7000) * np.exp(-tv(0.005) / r.uniform(0.0004, 0.001)),
              r.uniform(0.2, 1.0) ** 2 * (0.3 + 0.7 * t0 / dur(name)))
    x = 0.55 * bz + 0.35 * unit(cr) + 0.12 * noise(r, n, 3000, 8000) * u ** 2
    save(name, band(x, 80, 7500), fin=0.05, fout=0.03)

    # the bolt landing on a rod: a crack (rounded off, not a click), a deep boom, the span sizzling
    # live for half a second and a short rumble
    name = "tempest_lightning_strike"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = 0.8 * click(r, dur(name), 500, 7000, 0.006) + 0.7 * unit(tilt(r.standard_normal(n), -3.0)) * env(t, 0.0005, 0.03)
    x += 0.5 * thud(t, 90, 38, 0.15, 0.25, harm=(0.5, 0.25))
    hum = buzz_wave(100.0, n, 30, 1.0) * env(t, 0.002, 0.25)
    x += 0.25 * band(hum, None, 4000) + 0.35 * unit(sparks(r, dur(name), 120, 0.0, 0.5, 1500, 7000, decay=0.25))
    x += 0.5 * noise(r, n, 30, 250) * env(t, 0.03, 0.5)
    save(name, space(r, band(x, None, 9000), 1.8, 0.35, 80, 6000, predelay=0.02), fin=0.0005, fout=0.3)

    # the scaffold starting to go: steel tubes groaning, couplers rattling, the boards creaking and
    # the bay lurching
    name = "tempest_scaffold_creak"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = np.zeros(n)
    place(x, 0.0, iron_creak(r, 0.8, 320, (30.0, 90.0)), 1.0)
    place(x, 0.2, groan(r, 0.6, 170), 0.45)
    rt = np.zeros(n)
    for _ in range(10):
        place(rt, r.uniform(0.05, 0.8), modes(tv(0.08), bar_modes(r.uniform(1200, 2200), 0.02), r, 0.02, hard=4000), r.uniform(0.3, 1.0))
    x = unit(x) + 0.3 * unit(rt)
    for t0 in (0.0, 0.45):
        place(x, t0, thud(tv(0.2), 120, 80, 0.02, 0.05), 0.4)
    save(name, space(r, x, 0.9, 0.2, 150, 6000), fin=0.003, fout=0.15)

    # the bay dropping away: couplers snapping, the frame lurching, tubes and boards clanging and
    # clattering as they fall, duller and fainter as they go down into the cloud
    name = "tempest_scaffold_fall"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = np.zeros(n)
    for t0 in (0.0, 0.06):
        place(x, t0, modes(tv(0.3), bar_modes(r.uniform(700, 900), 0.08), r, 0.02, hard=4000) +
              0.6 * click(r, 0.3, 1000, 6000, 0.002), 0.7)
    place(x, 0.05, thud(tv(0.4), 110, 60, 0.04, 0.1), 0.7)
    for _ in range(16):
        t0 = 0.1 + r.gamma(1.6, 0.25)
        if t0 < dur(name) - 0.1:
            place(x, t0, modes(tv(0.3), bar_modes(r.uniform(300, 1100), 0.15), r, 0.03, hard=4000 * np.exp(-t0 / 0.8)),
                  0.5 * r.uniform(0.4, 1.0) * np.exp(-t0 / 0.6))
    for _ in range(14):
        t0 = 0.08 + r.gamma(1.5, 0.2)
        if t0 < dur(name) - 0.1:
            place(x, t0, wood_knock(r, 0.1, r.uniform(200, 500), 0.02, 3000), 0.4 * r.uniform(0.4, 1.0) * np.exp(-t0 / 0.6))
    x += 0.25 * whoosh(r, dur(name), 800, 900, 200, 0.2, 0.5)
    save(name, space(r, x, 1.4, 0.3, 100, 6000), fin=0.0008, fout=0.4)

    # the hook bell before a load moves off: a small hand bell on F#5 rung four times
    name = "tempest_load_bell"
    r = rng(name)
    t = tv(dur(name))
    x = np.zeros(len(t))
    for k, t0 in enumerate((0.0, 0.18, 0.36, 0.54)):
        place(x, max(t0 + r.uniform(-0.01, 0.01), 0.0), modes(tv(0.45), bell_modes(midi(78), 0.3), r, 0.004, hard=6000) +
              0.2 * click(r, 0.45, 2000, 6000, 0.001), 1.0 - 0.08 * k)
    save(name, space(r, x, 0.8, 0.15, 200, 7000), fin=0.0008, fout=0.2)

    # the gondola's hoist spooling up (the tell): a relay clunk, the brake letting go and the motor
    # winding up to its B2 hum with the gearbox whining after it
    name = "tempest_gondola_start"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    f = glide(25.0, midi(47), t, 0.8)
    mot = voice(f, n, 12, 1.0, 0.0, 1.0)
    whine = tone(f * 9.0)
    x = (0.6 * mot + 0.05 * whine) * np.clip((t - 0.05) / 0.7, 0, 1) ** 0.8
    place(x, 0.0, thud(tv(0.15), 180, 120, 0.01, 0.02) + 0.5 * click(r, 0.15, 1500, 6000, 0.001), 0.6)
    place(x, 0.15, modes(tv(0.2), bar_modes(r.uniform(900, 1100), 0.04), r, 0.02, hard=4000), 0.3)
    save(name, x, fin=0.0008, fout=0.12)

    # the gondola's hoist running (loop): a B2 motor hum, the gearbox whining, the cable ticking over
    # the drum and the cradle rattling on its cables
    name = "tempest_gondola_motor"
    r = rng(name)
    n = ns(dur(name))
    i = np.arange(n) / SR
    hum = hum_stack(n, cyc(midi(47), n), 12, 1.0, 1.4, r)
    gear = np.sin(TAU * cyc(midi(47) * 9.0, n) * i) * (0.7 + 0.3 * clfo(n, 6))
    ticks = np.zeros(n)
    for k in range(8):
        cplace(ticks, k / 8.0 * dur(name), modes(tv(0.04), bar_modes(r.uniform(1100, 1300), 0.012), r, 0.02) +
               0.3 * click(r, 0.04, 1200, 5000, 0.001), r.uniform(0.6, 1.0))
    rattle = np.zeros(n)
    grains(r, rattle, 40, 0.0, dur(name), 500, 2500, 0.002, 0.006, 1.0, wrap=True)
    save_loop(name, 0.6 * hum + 0.06 * gear + 0.25 * unit(ticks) + 0.15 * unit(rattle) + 0.15 * cnoise(r, n, 60, 400))

    # a crane trolley running (loop): wheels rumbling along the jib, the rail joints knocking twice
    # a loop, the winch motor whining on F#2 / F#5 and the hoist cable singing faintly
    name = "tempest_trolley"
    r = rng(name)
    n = ns(dur(name))
    i = np.arange(n) / SR
    rumble = cnoise(r, n, 50, 500) * (0.7 + 0.3 * crand(r, n, 10))
    cl = np.zeros(n)
    for t0 in (0.1, 0.6):
        cplace(cl, t0, thud(tv(0.08), 200, 130, 0.01, 0.015) + 0.5 * modes(tv(0.08), bar_modes(r.uniform(650, 750), 0.02), r, 0.02), 1.0)
    hum = hum_stack(n, cyc(midi(42), n), 10, 1.1, 1.3, r)
    whine = np.sin(TAU * cyc(midi(78), n) * i) * (0.8 + 0.2 * clfo(n, 4))
    sing = unit(csvf(r.standard_normal(n), cyc(1100, n), 25.0)) * (0.6 + 0.4 * crand(r, n, 5))
    save_loop(name, unit(rumble) + 0.5 * unit(cl) + 0.45 * hum + 0.05 * whine + 0.05 * sing)

    # the crane slewing (loop): the slewing ring's teeth meshing 18 times a second, a deep grinding
    # rumble, the B1 drive motor and the jib creaking twice a loop
    name = "tempest_crane_slew"
    r = rng(name)
    n = ns(dur(name))
    mesh = circ_creak(r, n, lambda u: 18.0, [(300, 1.0, 0.012), (720, 0.6, 0.008), (1500, 0.3, 0.005)])
    grind = cnoise(r, n, 25, 220) * (0.75 + 0.25 * crand(r, n, 8))
    mot = hum_stack(n, cyc(midi(35), n), 18, 0.8, 1.4, r)
    jib = np.zeros(n)
    for t0 in (0.2, 0.95):
        cplace(jib, t0, iron_creak(r, 0.45, 210, (15.0, 35.0)), r.uniform(0.7, 1.0))
    save_loop(name, 0.5 * mesh + 0.8 * unit(grind) + 0.6 * mot + 0.3 * unit(jib) + 0.15 * cnoise(r, n, 300, 1500) * (0.6 + 0.4 * crand(r, n, 9)))

    # the slew horn (the tell, 1.2 s ahead): two blasts of a B3/D4 site horn, echoing off the towers
    name = "tempest_crane_horn"
    r = rng(name)
    x = np.zeros(ns(dur(name)))
    place(x, 0.0, horn(r, 0.42, (59, 62), (650.0, 1700.0)), 1.0)
    place(x, 0.52, horn(r, 0.55, (59, 62), (650.0, 1700.0)), 1.0)
    save(name, space(r, band(x, None, 5000), 1.2, 0.3, 150, 4000, predelay=0.05), fin=0.002, fout=0.25)

    # a ram's tell (a second before it punches): the valve clacking open, hydraulic oil hissing
    # through it harder and harder, the pump whining up and the seal creaking
    name = "tempest_ram_hiss"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    u = t / dur(name)
    x = unit(tilt(noise(r, n, 700, 6000), -3.0)) * (0.2 + 0.8 * u ** 1.5)
    x += 0.15 * tone(glide(midi(66), midi(78), t, dur(name))) * u
    place(x, 0.0, thud(tv(0.1), 300, 180, 0.01, 0.015) + 0.6 * click(r, 0.1, 1500, 6000, 0.0012), 0.6)
    place(x, 0.4, iron_creak(r, 0.45, 600, (40.0, 90.0)), 0.15)
    save(name, x, fin=0.0008, fout=0.04)

    # a pile driver's tell: an exhaust valve clacking, steam chuffing out faster as the hammer is
    # hauled up, then a long rising hiss as it hangs, ready
    name = "tempest_driver_hiss"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = np.zeros(n)
    place(x, 0.0, thud(tv(0.15), 160, 90, 0.02, 0.03) + 0.5 * click(r, 0.15, 1000, 5000, 0.0015), 0.7)
    for k, t0 in enumerate((0.04, 0.3, 0.5)):
        tt = tv(0.22)
        place(x, t0, unit(tilt(noise(r, len(tt), 300, 6000), -2.5)) * env(tt, 0.008, 0.06), 0.7 - 0.1 * k)
    tt = tv(0.4)
    place(x, 0.6, unit(tilt(noise(r, len(tt), 400, 7000), -2.0)) * np.minimum(tt / 0.35, 1.0) ** 1.5, 0.6)
    x += 0.25 * noise(r, n, 60, 300) * env(t, 0.02, 0.4)
    save(name, x, fin=0.0008, fout=0.04)

    # thunder rolling in after a far strike: no crack, rolls of low rumble tearing across the sky
    name = "tempest_thunder"
    r = rng(name)
    t = tv(dur(name))
    x = thunder(r, dur(name), 0.0, 1.2, 1500.0) + 0.4 * thud(t, 60, 32, 0.2, 0.4, harm=(0.3,), attack=0.03)
    save(name, band(x, None, 1800), fin=0.03, fout=0.5)

    # a checkpoint: a steel clank (a beam ringing) and a short toot of the site horn on B4/D5
    name = "tempest_checkpoint"
    r = rng(name)
    t = tv(dur(name))
    x = np.zeros(len(t))
    place(x, 0.0, thud(tv(0.9), 140, 80, 0.02, 0.05) + 0.6 * modes(tv(0.9), plate_modes(r.uniform(240, 270), 2.5, 0.4, 10, 0.6, r), r, 0.02, hard=4000) +
          0.4 * click(r, 0.9, 1500, 6000, 0.0015), 0.8)
    place(x, 0.16, horn(r, 0.38, (71, 74), (800.0, 2000.0), 0.02, 0.02, 0.06), 0.8)
    save(name, space(r, band(x, None, 7000), 1.3, 0.3, 150, 5000), fin=0.0008, fout=0.25)

    # the finish: the bolt striking the beacon mast - a bigger crack and boom, the mast ringing and
    # the thunder rolling away round the city
    name = "tempest_finish_strike"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = 0.8 * click(r, dur(name), 400, 7000, 0.008) + 0.7 * unit(tilt(r.standard_normal(n), -3.0)) * env(t, 0.0005, 0.04)
    x += 0.55 * thud(t, 80, 30, 0.2, 0.35, harm=(0.5, 0.25))
    x += 0.3 * modes(t, bar_modes(r.uniform(160, 180), 0.6), r, 0.01, hard=3000)
    x += 0.3 * unit(sparks(r, dur(name), 150, 0.0, 0.6, 1500, 7000, decay=0.3))
    x += 0.6 * unit(thunder(r, dur(name), 0.15, 1.3, 1500.0))
    save(name, space(r, band(x, None, 9000), 2.0, 0.35, 60, 6000, predelay=0.02), fin=0.0005, fout=0.45)

    # the all-clear at the finish: a long site horn rising onto a B-minor chord (B3, then F#4 and B4
    # joining), echoing round the towers, with the wind behind it
    name = "tempest_beacon"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = np.zeros(n)
    for t0, m, g in ((0.0, 59, 1.0), (0.35, 66, 0.8), (0.7, 71, 0.7)):
        place(x, t0, horn(r, 1.6 - t0, (m,), (700.0, 1800.0), 0.03, 0.08, 0.35), g)
    y = unit(x)
    place(y, 0.45, band(x, None, 2500), 0.3)
    place(y, 0.95, band(x, None, 1500), 0.12)
    y += 0.08 * unit(tilt(noise(r, n, 80, 5000), -3.0)) * (0.6 + 0.4 * np.abs(noise(r, n, None, 2)))
    save(name, space(r, band(y, None, 5000), 1.6, 0.3, 120, 4000, predelay=0.04), fin=0.004, fout=0.45)


# ---------------------------------------------------------------------------
# The Void (score in F# minor): glass, light, stone that floats, and a dream coming apart.
# ---------------------------------------------------------------------------
def gen_void():
    # the solid set about to fade (0.95 s ahead): glassy ticks on F#6 / C#6 coming faster and
    # faster, and a shimmer flickering up behind them
    name = "void_phase_warn"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = np.zeros(n)
    tk, k = 0.0, 0
    while tk < dur(name) - 0.06:
        place(x, tk, tine(r, midi(90 if k % 2 == 0 else 85), 0.2, 0.25), 0.5 + 0.5 * tk / dur(name))
        tk += 0.16 * (1.0 - 0.7 * tk / dur(name))
        k += 1
    x = unit(x) + 0.12 * noise(r, n, 3000, 7000) * (t / dur(name)) ** 2 * (0.5 + 0.5 * np.sin(TAU * glide(8, 25, t, dur(name)) * t))
    save(name, space(r, x, 1.0, 0.3, 300, 7000), fin=0.0008, fout=0.08)

    # the two sets trading places: two glass tones crossing (A5 rising to C#6, C#6 falling to A5),
    # a soft breath of air and a hush of light
    name = "void_phase_swap"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = np.zeros(n)
    for f0, f1 in ((midi(81), midi(85)), (midi(85), midi(81))):
        f = glide(f0, f1, t, 0.12)
        ph = TAU * np.cumsum(f) / SR
        x += np.sin(ph + 0.7 * np.exp(-t / 0.06) * np.sin(2.76 * ph)) * env(t, 0.01, 0.18)
    x = 0.6 * unit(x) + 0.3 * whoosh(r, dur(name), 500, 2500, 1200, 0.1, 0.06, q=2.0)
    x += 0.08 * noise(r, n, 4000, 8000) * env(t, 0.03, 0.15)
    save(name, space(r, x, 1.2, 0.3, 300, 7000), fin=0.002, fout=0.12)

    # into a rift: a soft airy swell rising, a quick upward shimmer (F#5 A5 C#6 F#6) and a low
    # F#3 bloom under it as gravity lets go
    name = "void_rift_enter"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    air = unit(svf(r.standard_normal(n), glide(400, 2500, t, 0.5), 2.0)) * env(t, 0.25, 0.3)
    sh = np.zeros(n)
    for j, m in enumerate((78, 81, 85, 90)):
        place(sh, 0.05 + 0.05 * j, fm_glass(midi(m), 0.5, 0.2, 0.3, 2.0, 0.02), 0.5)
    low = tone(midi(54), t) * env(t, 0.2, 0.25)
    save(name, space(r, 0.6 * air + 0.4 * unit(sh) + 0.25 * low, 1.4, 0.35, 200, 7000), fin=0.004, fout=0.15)

    # the tumbling room getting ready to turn: stone grinding and creaking deep in its frame, the
    # room shuddering and grit trickling
    name = "void_tumble_warn"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    u = t / dur(name)
    grind = creak(r, dur(name), lambda v: 25.0 + 45.0 * v, [(90, 1.0, 0.03), (210, 0.7, 0.02), (470, 0.4, 0.012), (1000, 0.2, 0.006)])
    x = grind * (0.3 + 0.7 * u) * (0.75 + 0.25 * np.sin(TAU * 12.0 * t))
    x += 0.5 * noise(r, n, 30, 180) * (0.3 + 0.7 * u)
    g = np.zeros(n)
    grains(r, g, 40, 0.1, dur(name) - 0.05, 600, 3000, 0.002, 0.006, 1.0)
    x = unit(x) + 0.2 * unit(g) * u
    save(name, space(r, x, 0.9, 0.2, 100, 5000), fin=0.02, fout=0.06)

    # the room rolling over: a heavy rushing swing and the deep rumble of the mass turning
    name = "void_tumble_turn"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = whoosh(r, dur(name), 90, 500, 120, 0.3, 0.15, q=1.0)
    f = 45.0 + 15.0 * np.sin(np.pi * np.clip(t / 0.6, 0, 1))
    x += 0.6 * tone(f) * np.sin(np.pi * np.clip(t / 0.65, 0, 1)) ** 1.5
    x += 0.3 * noise(r, n, 40, 250) * np.sin(np.pi * np.clip(t / 0.65, 0, 1))
    save(name, x, fin=0.01, fout=0.15)

    # settling on its new floor: a soft boom, a puff of dust and a faint glassy ring
    name = "void_tumble_thud"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = 0.6 * thud(t, 95, 50, 0.08, 0.16) + 0.5 * noise(r, n, 200, 2000) * env(t, 0.005, 0.08) + 0.7 * modes(t, [(170, 1.0, 0.05), (395, 0.6, 0.03), (760, 0.3, 0.015)], r, 0.03, hard=1500)
    x += 0.1 * fm_glass(midi(78), dur(name), 0.4, 0.4)
    save(name, space(r, x, 0.8, 0.25, 100, 5000), fin=0.001, fout=0.2)

    # the collapse beginning: a deep tearing groan, the sky ripping (a ragged band of noise
    # swelling), glass cracking and a pair of dissonant tones (F#2 / G2) sinking a fourth
    name = "void_collapse_start"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = 0.8 * thud(t, 70, 30, 0.2, 0.4)
    gr = creak(r, 1.6, lambda v: 14.0 + 30.0 * np.sin(np.pi * v), [(60, 1.0, 0.04), (140, 0.7, 0.03), (310, 0.4, 0.02), (700, 0.2, 0.01)])
    place(x, 0.05, gr * np.sin(np.pi * np.linspace(0, 1, len(gr))) ** 0.8, 0.6)
    tear = noise(r, n, 300, 3000) * (0.3 + 0.7 * np.abs(noise(r, n, None, 25))) * env(t, 0.4, 0.6)
    sink = 2.0 ** (-5.0 / 12.0 * np.clip(t / 1.8, 0, 1))
    tones = (tone(midi(42) * sink) + tone(midi(43) * sink) + 0.4 * tone(2 * midi(42) * sink)) * env(t, 0.3, 0.8)
    x += 0.35 * unit(tear) + 0.3 * tones
    for t0 in (0.25, 0.6, 1.1):
        place(x, t0, pew(0.3, 3500, 700), 0.15)
    save(name, space(r, x, 2.2, 0.4, 60, 6000, predelay=0.03), fin=0.005, fout=0.4)

    # the collapse front (loop): a deep rumble of the world coming apart, two groans, glass cracking
    # and debris tumbling, over a low F#1 / G1 drone beating
    name = "void_collapse_rumble"
    r = rng(name)
    n = ns(dur(name))
    i = np.arange(n) / SR
    rumble = cnoise(r, n, 25, 250) * (0.6 + 0.4 * crand(r, n, 14, 0.5))
    drone = np.sin(TAU * cyc(midi(30), n) * i) + np.sin(TAU * cyc(midi(31), n) * i) + 0.5 * np.sin(TAU * cyc(midi(42), n) * i)
    gr = np.zeros(n)
    for t0, f0 in ((0.1, 75.0), (1.05, 60.0)):
        g = creak(r, 0.8, lambda v: 14.0 + 25.0 * np.sin(np.pi * v), [(f0, 1.0, 0.04), (f0 * 2.3, 0.6, 0.03), (f0 * 5.1, 0.3, 0.015)])
        cplace(gr, t0, taper(g * np.sin(np.pi * np.linspace(0, 1, len(g))), 0.02), 1.0)
    cr = np.zeros(n)
    for t0 in (0.45, 0.8, 1.4, 1.75):
        cplace(cr, t0, pew(0.25, r.uniform(2800, 4000), 700), r.uniform(0.5, 1.0))
    deb = np.zeros(n)
    for _ in range(30):
        cplace(deb, r.uniform(0, dur(name)), modes(tv(0.08), [(r.uniform(300, 1200), 1.0, 0.012)], r) +
               0.3 * click(r, 0.08, 500, 4000, 0.002), r.uniform(0.2, 1.0))
    save_loop(name, unit(rumble) + 0.3 * unit(drone) + 0.35 * unit(gr) + 0.15 * unit(cr) + 0.25 * unit(deb))

    # a step starting to go: glass and stone cracking (two dispersive "pew" cracks and a stony
    # crack) and a few tinkling shards
    name = "void_fragment_crack"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = np.zeros(n)
    place(x, 0.0, pew(0.25, 3000, 800), 0.3)
    place(x, 0.07, pew(0.2, 2600, 700), 0.22)
    place(x, 0.02, click(r, 0.12, 250, 3500, 0.004) + modes(tv(0.12), [(r.uniform(400, 700), 1.0, 0.02), (1100, 0.5, 0.01), (1700, 0.3, 0.006)], r), 0.7)
    for _ in range(8):
        place(x, r.uniform(0.05, 0.4), fm_glass(r.uniform(2000, 4000), 0.15, 0.04, 0.4, 2.3, 0.001), r.uniform(0.08, 0.22))
    save(name, space(r, band(x, None, 8000), 1.0, 0.25, 200, 7000), fin=0.0005, fout=0.12)

    # a step breaking away: a hollow crash, the slab's resonance, chips and shards scattering and
    # a soft shimmer sliding down as it falls and dissolves
    name = "void_fragment_fall"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = thud(t, 110, 60, 0.05, 0.12) + 0.6 * modes(t, [(180, 1.0, 0.15), (410, 0.6, 0.1), (690, 0.4, 0.06), (1150, 0.2, 0.04)], r, 0.02, hard=2500)
    x += 0.5 * click(r, dur(name), 300, 5000, 0.005)
    for _ in range(20):
        t0 = 0.02 + r.gamma(1.5, 0.08)
        if t0 < 0.8:
            place(x, t0, modes(tv(0.08), [(r.uniform(400, 1500), 1.0, 0.01)], r) + 0.3 * click(r, 0.08, 500, 4000, 0.0015), 0.3 * r.uniform(0.3, 1.0))
    for _ in range(12):
        place(x, r.uniform(0.02, 0.5), fm_glass(r.uniform(2500, 5000), 0.2, 0.06, 0.5, 2.3, 0.001), r.uniform(0.05, 0.2))
    fsl = glide(1200, 300, t, 0.9)
    x += 0.12 * tone(fsl) * env(t, 0.1, 0.35)
    save(name, space(r, band(x, None, 8000), 1.4, 0.3, 100, 7000), fin=0.0008, fout=0.25)

    # a checkpoint: a glassy bell bloom on F#5 A5 C#6 F#6 (soft-attacked, so it blooms) over an
    # F#4 swell, and a shower of light twinkling down
    name = "void_checkpoint"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = np.zeros(n)
    for j, m in enumerate((78, 81, 85, 90)):
        place(x, 0.04 * j, fm_glass(midi(m), 1.0, 0.4, 1.2, 2.76, 0.02), 0.6)
    x = unit(x) + 0.2 * tone(midi(66), t) * env(t, 0.12, 0.4)
    sh = np.zeros(n)
    for _ in range(60):
        t0 = 0.05 + r.gamma(1.5, 0.2)
        if t0 < dur(name) - 0.05:
            place(sh, t0, fm_glass(midi(int(r.choice([90, 93, 97, 102]))), 0.12, 0.03, 0.4, 2.0, 0.001), r.uniform(0.2, 1.0))
    x += 0.25 * unit(sh)
    save(name, space(r, band(x, None, 8000), 1.8, 0.4, 200, 7000), fin=0.002, fout=0.25)

    # the finish: the door in the sky opening - a choir of six voices entering one above another
    # (F#3 C#4 F#4 A4 C#5 F#5), each scooping up into its note, so the whole chord rises; and a
    # shimmer of breaking glass
    name = "void_finish"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    ch = np.zeros(n)
    for k, m in enumerate((54, 61, 66, 69, 73, 78)):
        t0 = 0.22 * k
        tt = tv(dur(name) - t0)
        f = midi(m) * 2.0 ** (-1.0 / 12.0 * np.exp(-tt / 0.15))
        v = voice(f, len(tt), 18, 1.4, 0.006, 5.0 + 0.3 * k, r)
        place(ch, t0, v * np.minimum(tt / 0.3, 1.0) * np.clip((dur(name) - t0 - tt) / 0.8, 0, 1), 1.0 - 0.08 * k)
    ch = unit(svf(ch, 750.0, 2.0) + 0.6 * svf(ch, 1150.0, 2.5) + 0.25 * band(ch, None, 3000))
    gl = np.zeros(n)
    for _ in range(80):
        t0 = 0.3 + r.gamma(1.6, 0.35)
        if t0 < dur(name) - 0.1:
            place(gl, t0, fm_glass(r.uniform(2500, 6000), 0.15, 0.04, 0.5, 2.3, 0.001), r.uniform(0.2, 1.0))
    for t0 in (0.3, 0.9):
        place(gl, t0, pew(0.3, 4000, 1000), 0.6)
    x = ch + 0.25 * unit(gl) + 0.06 * noise(r, n, 2000, 7000) * np.clip(t / 1.2, 0, 1)
    save(name, space(r, band(x, None, 8000), 2.6, 0.5, 100, 6000, predelay=0.04), fin=0.004, fout=0.5)

    # inside a rift (loop): a deep, breathing choral drone (F#2 C#3 F#3 A3, each against a copy
    # half a hertz away), air breathing in and out and a faint high shimmer
    name = "void_rift_hum"
    r = rng(name)
    n = ns(dur(name))
    i = np.arange(n) / SR
    ch = np.zeros(n)
    for m, g in ((42, 1.0), (49, 0.7), (54, 0.6), (57, 0.45)):
        f = cyc(midi(m), n)
        ch += g * (np.roll(buzz_wave(f, n, 16, 1.4), int(r.integers(0, n))) + np.roll(buzz_wave(f + 0.5, n, 16, 1.4), int(r.integers(0, n))))
    ch = unit(csvf(ch, 650.0, 2.0) + 0.5 * cband(ch, None, 1200))
    breath = 0.75 + 0.25 * clfo(n, 1)
    air = cnoise(r, n, 300, 3000) * (0.5 + 0.5 * clfo(n, 1, 1.0))
    sh = np.sin(TAU * cyc(midi(85), n) * i) * (0.5 + 0.5 * clfo(n, 3)) + np.sin(TAU * cyc(midi(90), n) * i) * (0.5 + 0.5 * clfo(n, 2, 2.0))
    save_loop(name, ch * breath + 0.15 * air + 0.05 * sh)


# ---------------------------------------------------------------------------
# Doom Fortress (score in C minor): a foundry fortress - iron, steam, molten metal, power.
# ---------------------------------------------------------------------------
def gen_doom():
    # a press / ram's tell (a second ahead): an iron warning bell clanged three times
    name = "doom_press_warn"
    r = rng(name)
    x = np.zeros(ns(dur(name)))
    for k, t0 in enumerate((0.0, 0.24, 0.48)):
        place(x, t0, modes(tv(0.4), bell_modes(midi(79), 0.25), r, 0.004, hard=5000) + 0.3 * click(r, 0.4, 1500, 6000, 0.0012),
              1.0 - 0.05 * k)
    save(name, space(r, band(x, None, 7000), 1.2, 0.25, 150, 5000), fin=0.0008, fout=0.2)

    # the lockdown klaxon (1.2 s ahead): two whoops of a buzzy horn rising G3 -> Eb4, in the hall
    name = "doom_klaxon"
    r = rng(name)
    x = np.zeros(ns(dur(name)))
    for t0 in (0.0, 0.58):
        tt = tv(0.52)
        f = midi(55) * 2.0 ** (8.0 / 12.0 * np.clip(tt / 0.35, 0, 1) ** 0.7)
        v = voice(f, len(tt), 22, 0.9, 0.0, 1.0)
        v = unit(svf(v, 1000.0, 1.5) + 0.5 * band(v, None, 2500))
        place(x, t0, taper(v * np.minimum(tt / 0.02, 1.0) * np.clip((0.52 - tt) / 0.06, 0, 1)), 1.0)
    save(name, space(r, band(x, None, 4500), 1.5, 0.3, 150, 4000, predelay=0.03), fin=0.002, fout=0.2)

    # the grates slamming live: a heavy contactor clunk, an electrical thump, the mains buzz biting
    # in and a spit of sparks
    name = "doom_lockdown"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = thud(t, 90, 35, 0.1, 0.18, harm=(0.5, 0.25)) + 0.6 * click(r, dur(name), 400, 5000, 0.004)
    x += 0.4 * modes(t, plate_modes(r.uniform(300, 340), 1.6, 0.15, 8, 0.7, r), r, 0.02, hard=3000)
    bz = band(buzz_wave(100.0, n, 30, 1.0), 80, 4000) * env(t, 0.01, 0.35) * (0.8 + 0.2 * np.sin(TAU * 7 * t))
    x += 0.4 * bz + 0.3 * unit(sparks(r, dur(name), 90, 0.0, 0.6, 1500, 7000, decay=0.2))
    save(name, space(r, x, 1.5, 0.3, 100, 5000), fin=0.0008, fout=0.3)

    # the all-clear: the power dropping out of the grates (the buzz sinking away) and a three-note
    # chime rising C5 Eb5 G5
    name = "doom_alarm_clear"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    f = glide(100.0, 40.0, t, 0.4)
    ph = TAU * np.cumsum(f) / SR
    bz = np.zeros(n)
    for k in range(1, 20):
        bz += np.sin(k * ph) / k
    x = 0.3 * band(unit(bz), None, 3000) * env(t, 0.005, 0.12)
    for j, m in enumerate((72, 75, 79)):
        place(x, 0.12 + 0.14 * j, fm_glass(midi(m), 0.7, 0.3, 0.6, 3.5, 0.002), 0.5)
    save(name, space(r, x, 1.4, 0.3, 200, 6000), fin=0.001, fout=0.2)

    # a catwalk section about to go: two bolts shearing with a ping, the grating lurching and its
    # steel groaning, and a few sparks
    name = "doom_catwalk_creak"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = np.zeros(n)
    for t0 in (0.0, 0.18):
        place(x, t0, modes(tv(0.3), bar_modes(r.uniform(1500, 1900), 0.06), r, 0.02, hard=3500) + 0.5 * click(r, 0.3, 1500, 6000, 0.001), 0.6)
    place(x, 0.04, thud(tv(0.3), 130, 80, 0.02, 0.05) + 0.4 * modes(tv(0.3), plate_modes(300, 3.0, 0.1, 8, 0.7, r), r, 0.02, hard=3000), 0.7)
    place(x, 0.1, iron_creak(r, 0.65, 260, (40.0, 110.0)), 0.6)
    x += 0.2 * unit(sparks(r, dur(name), 25, 0.0, 0.3, 2000, 7000))
    save(name, space(r, x, 1.2, 0.25, 150, 5000), fin=0.0008, fout=0.15)

    # the catwalk tearing loose: steel ripping, a big clang, and the section clanging away down the
    # pit, duller each time
    name = "doom_catwalk_fall"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = np.zeros(n)
    rip = creak(r, 0.25, lambda u: 120.0 + 180.0 * u, [(420, 1.0, 0.015), (980, 0.6, 0.01), (2100, 0.3, 0.006)])
    place(x, 0.0, rip * np.hanning(len(rip)) ** 0.5, 0.6)
    place(x, 0.2, thud(tv(0.8), 120, 55, 0.04, 0.12) + 0.8 * modes(tv(0.8), plate_modes(r.uniform(210, 240), 2.8, 0.3, 10, 0.6, r), r, 0.02, hard=3500), 1.0)
    for t0, g, hd in ((0.6, 0.55, 2500), (0.9, 0.35, 1800), (1.15, 0.2, 1200)):
        place(x, t0, modes(tv(0.4), plate_modes(r.uniform(200, 260), 2.8, 0.2, 8, 0.6, r), r, 0.02, hard=hd) +
              0.4 * thud(tv(0.4), 100, 60, 0.03, 0.06), g)
    x += 0.15 * whoosh(r, dur(name), 600, 700, 200, 0.3, 0.35)
    save(name, space(r, x, 1.8, 0.35, 80, 5000), fin=0.0008, fout=0.3)

    # the crucible starting to tip (1.2 s ahead): its chains groaning and rattling, the trunnions
    # grinding, the melt gloop-ing heavily and sparks spilling over the lip
    name = "doom_pour_tilt"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = np.zeros(n)
    place(x, 0.0, iron_creak(r, 1.1, 120, (15.0, 40.0)), 1.0)
    ch = np.zeros(n)
    for _ in range(14):
        place(ch, r.uniform(0.05, 1.0), modes(tv(0.1), bar_modes(r.uniform(800, 1200), 0.03), r, 0.02, hard=3000), r.uniform(0.3, 1.0))
    gl = np.zeros(n)
    for _ in range(8):
        place(gl, r.uniform(0.2, 1.1), bubble(r.uniform(70, 160), 0.2, r.uniform(0.04, 0.07), 0.3), r.uniform(0.5, 1.0))
    x = unit(x) + 0.25 * unit(ch) + 0.4 * unit(gl) + 0.15 * unit(sparks(r, dur(name), 50, 0.5, 1.2, 2000, 7000))
    save(name, space(r, x, 1.4, 0.3, 100, 5000), fin=0.005, fout=0.12)

    # the first gout of metal hitting the lane: a heavy, thick splat, a sizzle flaring up, slow
    # bubbles of slag bursting and a spray of sparks
    name = "doom_pour_splash"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = thud(t, 100, 45, 0.06, 0.12, harm=(0.4,)) + 0.6 * noise(r, n, 80, 800) * env(t, 0.005, 0.12)
    x += 0.4 * unit(tilt(noise(r, n, 1500, 7000), -2.0)) * env(t, 0.02, 0.45)
    for _ in range(8):
        place(x, r.uniform(0.1, 0.9), bubble(r.uniform(60, 150), 0.2, r.uniform(0.04, 0.07), 0.3), r.uniform(0.2, 0.5))
    x += 0.3 * unit(sparks(r, dur(name), 120, 0.0, 0.8, 2000, 7000, decay=0.3))
    save(name, space(r, x, 1.4, 0.3, 80, 5000), fin=0.001, fout=0.3)

    # molten metal rushing down the lane (loop): a thick low roar, viscous gloops, the sizzle and
    # sparks spitting off the front
    name = "doom_pour_loop"
    r = rng(name)
    n = ns(dur(name))
    roar = water_roar(r, n, 30, 1500, -4.0, 0.3)
    gl = np.zeros(n)
    for _ in range(25):
        cplace(gl, r.uniform(0, dur(name)), bubble(r.uniform(60, 200), 0.2, r.uniform(0.03, 0.06), 0.3), r.uniform(0.3, 1.0))
    sizzle = cnoise(r, n, 2000, 7000) * (0.6 + 0.4 * crand(r, n, 20))
    sp = crackle(r, dur(name), 60, 2000, 7000, wrap=True, n=n)
    save_loop(name, roar + 0.45 * unit(gl) + 0.12 * sizzle + 0.2 * unit(sp))

    # a tier's emitter charging (1.2 s ahead): a whine climbing C4 -> C6, a buzz throbbing faster and
    # crackles thickening
    name = "doom_reactor_charge"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    u = t / dur(name)
    f = midi(60) * 4.0 ** (u ** 1.3)
    whine = (tone(f) + 0.3 * tone(2 * f) + 0.1 * tone(3 * f)) * (0.2 + 0.8 * u ** 1.3)
    thr = 0.6 + 0.4 * np.sin(TAU * np.cumsum(4.0 + 16.0 * u) / SR)
    bz = band(buzz_wave(midi(36), n, 30, 1.0), None, 3000) * thr * (0.3 + 0.7 * u)
    cr = np.zeros(n)
    for _ in range(140):
        t0 = dur(name) * r.uniform(0, 1) ** 0.5
        place(cr, t0, noise(r, ns(0.005), 2000, 7000) * np.exp(-tv(0.005) / r.uniform(0.0004, 0.001)), r.uniform(0.2, 1.0) ** 2 * t0 / dur(name))
    save(name, band(0.3 * unit(whine) + 0.45 * bz + 0.3 * unit(cr), 60, 7500), fin=0.04, fout=0.03)

    # the ring of energy cracking out across a tier: an electric crack, a deep boom and a "whum"
    # sweeping down as the ring rushes outward, crackling away
    name = "doom_reactor_pulse"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = 0.6 * click(r, dur(name), 500, 6000, 0.005) + 0.9 * thud(t, 95, 40, 0.12, 0.2, harm=(0.5, 0.25))
    f = glide(600, 80, t, 0.5)
    ph = TAU * np.cumsum(f) / SR
    wh = np.zeros(n)
    for k in range(1, 10):
        wh += np.sin(k * ph) / k ** 1.5
    x += 0.4 * unit(wh) * env(t, 0.01, 0.25) + 0.3 * whoosh(r, dur(name), 1500, 2000, 300, 0.05, 0.15)
    x += 0.25 * unit(sparks(r, dur(name), 100, 0.0, 0.8, 1500, 6500, decay=0.3))
    save(name, space(r, band(x, None, 8000), 1.8, 0.35, 80, 5000), fin=0.0005, fout=0.3)

    # the reactor core (loop): a deep C2 hum throbbing twice a second, a copy half a hertz away
    # beating against it, a faint high whine on G5 and sparse crackle
    name = "doom_reactor_hum"
    r = rng(name)
    n = ns(dur(name))
    i = np.arange(n) / SR
    hum = hum_stack(n, cyc(midi(36), n), 20, 0.8, 1.3, r) + 0.7 * hum_stack(n, cyc(midi(36), n) + 0.5, 10, 1.1, 1.2, r)
    sub = np.sin(TAU * cyc(midi(24), n) * i)
    throb = 0.7 + 0.3 * clfo(n, 4)
    whine = np.sin(TAU * cyc(midi(79), n) * i) * (0.6 + 0.4 * clfo(n, 2))
    cr = crackle(r, dur(name), 25, 2000, 6000, wrap=True, n=n)
    save_loop(name, (unit(hum) + 0.3 * sub) * throb + 0.07 * whine + 0.12 * unit(cr) + 0.1 * cnoise(r, n, 40, 300))

    # a steam vent's tell (1 s ahead): pressure hissing up through the bars, the valve chattering and
    # a whistle rising G5 -> C6 as it builds
    name = "doom_vent_hiss"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    u = t / dur(name)
    hiss = unit(tilt(noise(r, n, 500, 7000), -3.0)) * (0.2 + 0.8 * u ** 1.5)
    fw = glide(midi(79), midi(84), t, dur(name))
    wh = (tone(fw) + 0.15 * tone(2 * fw)) * (0.7 + 0.3 * np.abs(noise(r, n, None, 40))) * u ** 2
    ch = np.zeros(n)
    tk = 0.0
    while tk < 0.5:
        place(ch, tk, modes(tv(0.03), bar_modes(r.uniform(1100, 1400), 0.01), r, 0.02) * 0.5 + 0.3 * click(r, 0.03, 800, 4000, 0.001), r.uniform(0.4, 1.0))
        tk += 1.0 / 28.0 * r.uniform(0.8, 1.2)
    save(name, hiss + 0.18 * wh + 0.25 * unit(ch) * np.exp(-t / 0.3), fin=0.003, fout=0.04)

    # the steam jet roaring out: a thump of pressure, a big burst of hiss settling, a roar under it
    # and a spit of water
    name = "doom_vent_blast"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = 0.7 * thud(t, 110, 55, 0.05, 0.1) + unit(tilt(noise(r, n, 500, 8000), -2.5)) * env(t, 0.01, 0.5)
    x += 0.5 * noise(r, n, 80, 600) * env(t, 0.02, 0.45)
    for _ in range(20):
        place(x, r.uniform(0.02, 0.6), ga.grain(r, 0.02, 600, 3000, 0.004), r.uniform(0.05, 0.2))
    save(name, x, fin=0.001, fout=0.3)

    # an electrified grate (loop): the mains buzz through the bars flickering, sparks crackling,
    # a sizzle surging and four short arcs
    name = "doom_grate_buzz"
    r = rng(name)
    n = ns(dur(name))
    bz = cband(buzz_wave(cyc(100.0, n), n, 30, 1.0, 0.7), 80, 4000) * (0.8 + 0.2 * crand(r, n, 15))
    cr = crackle(r, dur(name), 120, 1500, 6000, wrap=True, n=n)
    sz = cnoise(r, n, 3000, 7000) * (0.3 + 0.7 * (0.5 + 0.5 * crand(r, n, 10)) ** 2)
    arcs = np.zeros(n)
    for _ in range(4):
        tt = tv(0.06)
        cplace(arcs, r.uniform(0, dur(name)), taper(band(buzz_wave(r.uniform(180, 260), len(tt), 20, 0.9), None, 5000) * np.hanning(len(tt))), r.uniform(0.5, 1.0))
    save_loop(name, unit(bz) + 0.4 * unit(cr) + 0.12 * sz + 0.35 * unit(arcs))

    # the great gear turning (loop): its bearing grinding (a slow stick-slip through iron), a deep
    # rumble, three heavy tooth knocks a loop and the iron groaning once
    name = "doom_gear_grind"
    r = rng(name)
    n = ns(dur(name))
    grind = circ_creak(r, n, lambda u: 70.0, [(140, 1.0, 0.03), (330, 0.7, 0.02), (780, 0.4, 0.012), (1500, 0.2, 0.006)])
    rumble = cnoise(r, n, 25, 200) * (0.75 + 0.25 * crand(r, n, 6))
    kn = np.zeros(n)
    for k in range(3):
        cplace(kn, k * dur(name) / 3.0 + 0.1, thud(tv(0.25), 120, 70, 0.02, 0.05) +
               0.4 * modes(tv(0.25), bar_modes(r.uniform(400, 480), 0.08), r, 0.02, hard=2500), r.uniform(0.8, 1.0))
    gr = np.zeros(n)
    cplace(gr, 0.7, iron_creak(r, 0.7, 110, (15.0, 35.0)), 1.0)
    save_loop(name, grind + 0.55 * unit(rumble) + 0.5 * unit(kn) + 0.3 * unit(gr))

    # a checkpoint: a heavy relay clunk, its plate ringing briefly, a C4/G4 power-up tone and a hiss
    # of steam venting
    name = "doom_checkpoint"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = thud(t, 150, 70, 0.02, 0.06) + 0.6 * click(r, dur(name), 800, 5000, 0.002)
    x += 0.4 * modes(t, plate_modes(r.uniform(380, 420), 1.5, 0.2, 8, 0.7, r), r, 0.02, hard=4000)
    x += 0.15 * (tone(midi(60), t) + 0.7 * tone(midi(67), t)) * env(t, 0.06, 0.35)
    tt = tv(0.9)
    place(x, 0.1, unit(tilt(noise(r, len(tt), 800, 8000), -2.0)) * env(tt, 0.03, 0.3), 0.45)
    save(name, space(r, x, 1.4, 0.3, 100, 5000), fin=0.0008, fout=0.25)

    # the finish: the off switch thrown - a huge relay clunk, sparks, the steam let go, and the
    # whole machine spinning down (the core's hum sinking C2 -> C1 and a turbine whine falling away)
    name = "doom_finish"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = thud(t, 110, 40, 0.06, 0.2, harm=(0.5, 0.25)) + 0.6 * click(r, dur(name), 500, 5000, 0.004)
    x += 0.4 * modes(t, plate_modes(r.uniform(250, 280), 1.8, 0.3, 10, 0.6, r), r, 0.02, hard=3500)
    x += 0.25 * unit(sparks(r, dur(name), 120, 0.0, 0.5, 1500, 6500, decay=0.2))
    fdown = midi(36) * 0.5 ** np.clip(t / 2.2, 0, 1) ** 0.8
    core = voice(fdown, n, 14, 1.1, 0.0, 1.0) * np.clip((2.6 - t) / 2.4, 0, 1) ** 1.2
    tw = turbine(t, 900, 70, 2.2) * np.exp(-t / 0.9)
    tt = tv(1.4)
    place(x, 0.25, unit(tilt(noise(r, len(tt), 500, 8000), -2.0)) * env(tt, 0.05, 0.4), 0.3)
    place(x, 2.2, thud(tv(0.5), 70, 45, 0.05, 0.15), 0.3)
    x += 0.5 * band(core, None, 2500) + 0.12 * tw
    save(name, space(r, x, 2.2, 0.35, 60, 5000, predelay=0.03), fin=0.0008, fout=0.35)


# ===========================================================================
# the kit obstacles (docs/KIT_OBSTACLES.md) - gen_kit
# ===========================================================================
def gen_kit():
    # the barrel: the hatch clunks shut on you, the hollow staves ring and the air is pushed in
    name = "kit_barrel_load"
    r = rng(name)
    t = tv(dur(name))
    x = thud(t, 150, 60, 0.05, 0.08) + 0.6 * click(r, dur(name), 600, 5000, 0.003)
    x += 0.35 * modes(t, bar_modes(260.0, 0.25), r, 0.02, hard=2500)
    x += 0.3 * whoosh(r, dur(name), 300, 900, 200, 0.5, 0.25)
    save(name, space(r, x, 0.8, 0.2, 120, 4000), fin=0.002, fout=0.15)

    # one tick of the fuse (played every 0.2 s while it burns down)
    name = "kit_barrel_fuse"
    r = rng(name)
    t = tv(dur(name))
    x = click(r, dur(name), 1500, 6000, 0.0025) + 0.35 * tone(2600.0, t) * env(t, 0.0008, 0.003)
    save(name, x, fin=0.0005, fout=0.01)

    # the launch: a black-powder crack and thump, and the rush of air up the barrel
    name = "kit_barrel_fire"
    r = rng(name)
    x = cannon_boom(r, dur(name), 85.0, 0.8) + 0.6 * whoosh(r, dur(name), 350.0, 2200.0, 700.0, 0.25, 0.35)
    save(name, space(r, x, 1.2, 0.25, 100, 5000, predelay=0.02), fin=0.001, fout=0.25)

    # the zipline's lamp comes on: a bright glass ping and a rattle of the trolley
    name = "kit_zipline_ready"
    r = rng(name)
    x = fm_glass(midi(84), dur(name), 0.2, 0.5)
    for t0 in (0.06, 0.16, 0.26):
        place(x, t0, click(r, 0.03, 2000, 7000, 0.002), 0.4)
    save(name, x, fin=0.001, fout=0.1)

    # the hands clamp on the grip: a clack, a thump and the rope snapping taut
    name = "kit_zipline_grab"
    r = rng(name)
    t = tv(dur(name))
    x = click(r, dur(name), 800, 6000, 0.004) + 0.5 * thud(t, 260, 120, 0.02, 0.04, harm=(0.3, 0.1))
    x += 0.4 * whoosh(r, dur(name), 500, 1800, 900, 0.12, 0.08)
    save(name, x, fin=0.0008, fout=0.12)

    # the let-go: the rope springing free and a whoosh away
    name = "kit_zipline_release"
    r = rng(name)
    x = whoosh(r, dur(name), 900, 3000, 1200, 0.12, 0.12) + 0.4 * click(r, dur(name), 1000, 7000, 0.003)
    save(name, x, fin=0.001, fout=0.1)

    # the trolley riding the cable (loop): wheels ticking over the wire, a steady pulley hum
    name = "kit_zipline_whirr"
    r = rng(name)
    n = ns(dur(name))
    t = tv(dur(name))
    wheel = cband(r.standard_normal(n), 2500, 7000) * (0.7 + 0.3 * clfo(n, 12))
    hum = tone(cyc(190.0, n), t) + 0.4 * tone(cyc(380.0, n), t)
    save_loop(name, 0.6 * unit(wheel) + 0.4 * unit(hum))

    # the cannon's fuse: a fizz that builds and a spit of sparks
    name = "kit_battery_fuse"
    r = rng(name)
    t = tv(dur(name))
    fizz = noise(r, len(t), 2000, 8000) * np.clip(t / dur(name), 0.0, 1.0) ** 1.5
    x = 0.6 * fizz + 0.8 * sparks(r, dur(name), 16, 0.0, 0.6, 1500, 6000)
    save(name, x, fin=0.002, fout=0.1)

    # one salvo: a cannon pop with a short tail
    name = "kit_battery_fire"
    r = rng(name)
    x = cannon_boom(r, dur(name), 120.0, 0.55)
    save(name, space(r, x, 0.5, 0.15, 150, 5000), fin=0.0005, fout=0.12)

    # the log rolling (loop): a low rumble of bark on the ground and a knock every stride
    name = "kit_log_roll"
    r = rng(name)
    n = ns(dur(name))
    rumble = cnoise(r, n, 60, 380) * (0.8 + 0.2 * crand(r, n, 5))
    kn = np.zeros(n)
    for k in range(6):
        cplace(kn, k * dur(name) / 6.0 + r.uniform(0.0, 0.02), wood_knock(r, 0.12, r.uniform(150.0, 220.0), 0.02, 3000.0),
               r.uniform(0.6, 1.0))
    save_loop(name, unit(rumble) + 0.5 * unit(kn))

    # the log reversing: a long timber groan and the thunk of it catching
    name = "kit_log_reverse"
    r = rng(name)
    t = tv(dur(name))
    x = groan(r, dur(name), 120.0, 1.0, (25.0, 50.0)) + thud(t, 110, 50, 0.04, 0.07, harm=(0.4, 0.15))
    save(name, x, fin=0.002, fout=0.1)

    # the plank hits the ground
    name = "kit_seesaw_thunk"
    r = rng(name)
    t = tv(dur(name))
    x = thud(t, 170, 65, 0.03, 0.07, harm=(0.4, 0.15)) + 0.5 * modes(t, bar_modes(230.0, 0.12), r, 0.02, hard=2500)
    x += 0.5 * click(r, dur(name), 800, 4000, 0.004)
    save(name, space(r, x, 0.6, 0.2, 120, 4000), fin=0.001, fout=0.1)

    # the flipper winds back: an electric whine climbing and a ratchet's clicks
    name = "kit_flipper_tell"
    r = rng(name)
    t = tv(dur(name))
    x = 0.45 * turbine(t, 240.0, 560.0, dur(name) * 0.9, (1.0, 2.0, 3.02)) * env(t, 0.03, 0.5)
    for k in range(5):
        place(x, 0.04 + 0.09 * k, click(r, 0.02, 2500, 7000, 0.002), 0.6)
    save(name, x, fin=0.002, fout=0.1)

    # the swat: a heavy whack, a crack of click and a whoosh of the paddle through the air
    name = "kit_flipper_swat"
    r = rng(name)
    t = tv(dur(name))
    x = thud(t, 190, 90, 0.02, 0.05) + 0.7 * click(r, dur(name), 1000, 6000, 0.003)
    x += 0.5 * whoosh(r, dur(name), 400, 2000, 600, 0.08, 0.05)
    save(name, x, fin=0.0005, fout=0.08)

    # the paddle settles on its stop: a spring boing and a small rattle
    name = "kit_flipper_return"
    r = rng(name)
    t = tv(dur(name))
    x = modes(t, bar_modes(340.0, 0.09), r, 0.02, hard=3000) + 0.4 * thud(t, 160, 110, 0.02, 0.05)
    x += 0.3 * click(r, dur(name), 1500, 6000, 0.002)
    save(name, x, fin=0.001, fout=0.1)

    # the chains rattle through the warning: loose links clinking over an iron creak
    name = "kit_drawbridge_chains"
    r = rng(name)
    x = iron_creak(r, dur(name), 180.0, (14.0, 30.0)) * 0.4
    for _ in range(16):
        place(x, r.uniform(0.0, dur(name) - 0.06), click(r, 0.05, 2000, 7000, 0.003), r.uniform(0.3, 1.0))
    save(name, x, fin=0.002, fout=0.1)

    # the deck rises: a winch whine climbing, the chains dragging taut and iron complaining
    name = "kit_drawbridge_raise"
    r = rng(name)
    n = ns(dur(name))
    t = tv(dur(name))
    winch = voice(glide(110.0, 170.0, t, dur(name)), n, 10, 1.4, 0.001, 5.0, r)
    x = 0.4 * winch * np.clip((dur(name) - t) / 0.15, 0.0, 1.0)
    x += 0.5 * iron_creak(r, dur(name), 150.0, (12.0, 26.0))
    for k in range(int(dur(name) * 6)):
        place(x, k / 6.0 + 0.02, click(r, 0.02, 2000, 7000, 0.003), 0.25)
    save(name, x, fin=0.002, fout=0.12)

    # the deck lowers: the winch paying out, falling from a whine to a growl, with a groan of timber
    name = "kit_drawbridge_lower"
    r = rng(name)
    n = ns(dur(name))
    t = tv(dur(name))
    winch = voice(glide(170.0, 100.0, t, dur(name)), n, 10, 1.4, 0.001, 5.0, r)
    x = 0.4 * winch * np.clip(t / 0.1, 0.0, 1.0) * np.clip((dur(name) - t) / 0.15, 0.0, 1.0)
    x += 0.4 * groan(r, dur(name), 110.0, 1.0, (15.0, 30.0))
    save(name, x, fin=0.002, fout=0.12)

    # the deck slams down: a heavy thud and the timber boom under it
    name = "kit_drawbridge_thud"
    r = rng(name)
    t = tv(dur(name))
    x = thud(t, 75, 38, 0.1, 0.18, harm=(0.5, 0.25)) + 0.6 * click(r, dur(name), 300, 3000, 0.006)
    x += 0.4 * modes(t, bar_modes(120.0, 0.2), r, 0.02, hard=1500)
    save(name, space(r, x, 0.8, 0.2, 80, 2500), fin=0.0008, fout=0.2)

    # the amber lamp: two warning beeps
    name = "kit_gapwall_warn"
    x = np.zeros(ns(dur(name)))
    for t0 in (0.0, 0.4):
        tt = tv(0.3)
        beep = (tone(740.0, tt) + 0.25 * tone(1480.0, tt)) * np.minimum(tt / 0.006, 1.0) * np.clip((0.3 - tt) / 0.03, 0.0, 1.0)
        place(x, t0, beep, 0.8)
    save(name, x, fin=0.001, fout=0.05)

    # the wall slides shut: a stone slab grinding sideways along its rails
    name = "kit_gapwall_slide"
    r = rng(name)
    n = ns(dur(name))
    t = tv(dur(name))
    grind = creak(r, dur(name), lambda u: 28.0, [(90.0, 1.0, 0.03), (260.0, 0.6, 0.02), (700.0, 0.3, 0.01)])
    rail = noise(r, n, 200, 1500) * (0.6 + 0.4 * np.sin(TAU * 6.0 * t))
    x = 0.8 * grind + 0.4 * rail
    save(name, x, fin=0.01, fout=0.1)

    # the wall lands: a stone thud and a dull ring from the frame
    name = "kit_gapwall_thud"
    r = rng(name)
    t = tv(dur(name))
    x = thud(t, 110, 45, 0.05, 0.1, harm=(0.4, 0.15)) + 0.5 * click(r, dur(name), 300, 3000, 0.006)
    x += 0.35 * modes(t, bar_modes(150.0, 0.12), r, 0.02, hard=2000)
    save(name, space(r, x, 0.6, 0.2, 90, 3000), fin=0.0008, fout=0.15)

    # the block's winch cocks it: a rising whine that pulses on and off as a warning
    name = "kit_block_tell"
    t = tv(dur(name))
    f = glide(420.0, 900.0, t, dur(name))
    gate = 0.5 + 0.5 * np.clip(40.0 * np.sin(TAU * t / 0.45), -1.0, 1.0)
    x = (0.6 * tone(f) + 0.3 * tone(f * 2.0)) * gate * np.minimum(t / 0.01, 1.0)
    save(name, x, fin=0.002, fout=0.08)

    # the block drops: a heavy slam into the floor, a plate ringing and dust hissing off
    name = "kit_block_slam"
    r = rng(name)
    n = ns(dur(name))
    t = tv(dur(name))
    x = thud(t, 85, 30, 0.12, 0.2, harm=(0.5, 0.25)) + 0.5 * click(r, dur(name), 200, 4000, 0.006)
    x += 0.35 * modes(t, plate_modes(r.uniform(160.0, 200.0), 1.8, 0.2, 8, 0.7, r), r, 0.02, hard=2500)
    x += 0.35 * noise(r, n, 60, 900) * env(t, 0.002, 0.25)
    save(name, space(r, x, 1.3, 0.25, 80, 3000, predelay=0.02), fin=0.0008, fout=0.2)

    # the block is hauled back up: a hydraulic hiss and a whirr climbing, then a clank at the top
    name = "kit_block_rise"
    r = rng(name)
    n = ns(dur(name))
    t = tv(dur(name))
    hiss = noise(r, n, 1500, 6000) * np.clip(t / dur(name), 0.0, 1.0) ** 1.2
    whirr = voice(glide(120.0, 200.0, t, dur(name)), n, 6, 1.6, 0.001, 5.0, r)
    x = 0.3 * hiss + 0.3 * whirr
    place(x, dur(name) - 0.1, click(r, 0.1, 500, 3000, 0.02), 1.0)
    save(name, x, fin=0.002, fout=0.1)

    # the hammer winds back: a grinding bearing and a rising whine
    name = "kit_hammer_tell"
    r = rng(name)
    n = ns(dur(name))
    t = tv(dur(name))
    x = 0.45 * iron_creak(r, dur(name), 210.0, (8.0, 22.0))
    x += 0.4 * voice(glide(160.0, 380.0, t, dur(name)), n, 8, 1.5, 0.001, 5.0, r) * env(t, 0.05, 0.8)
    save(name, x, fin=0.002, fout=0.12)

    # the head whips past and strikes: a whoosh, a thud and the clang of iron
    name = "kit_hammer_swing"
    r = rng(name)
    t = tv(dur(name))
    x = whoosh(r, dur(name), 300, 1500, 500, 0.4, 0.15)
    x += 0.6 * thud(t, 120, 60, 0.03, 0.06) + 0.35 * modes(t, bar_modes(640.0, 0.35), r, 0.01, hard=4000)
    save(name, x, fin=0.001, fout=0.12)

    # the head clunks into its rest
    name = "kit_hammer_park"
    r = rng(name)
    t = tv(dur(name))
    x = thud(t, 160, 80, 0.03, 0.06, harm=(0.4, 0.15)) + 0.5 * click(r, dur(name), 800, 5000, 0.003)
    x += 0.3 * modes(t, bar_modes(480.0, 0.08), r, 0.01, hard=3000)
    save(name, x, fin=0.0008, fout=0.12)


# ===========================================================================
# the emotes and poses - gen_emotes (one clip per id: emote_<id>)
# ===========================================================================
def whistle(f0, f1, secs, vib=0.012):
    """A cheery whistled note: a sine gliding f0 -> f1 with a little vibrato and a soft second partial."""
    t = tv(secs)
    f = glide(f0, f1, t, secs * 0.6) * (1.0 + vib * np.sin(TAU * 6.0 * t))
    x = tone(f) + 0.12 * tone(f * 2.0)
    return taper(unit(x) * np.minimum(t / 0.03, 1.0) * np.clip((secs - t) / 0.08, 0.0, 1.0))


def pluck(f, secs, tau=0.09):
    """A plucked bass note: a bright buzzy tone that dies away fast."""
    t = tv(secs)
    v = voice(f, len(t), 12, 1.2, 0.0, 5.0)
    return taper(svf(v, f * 3.0, 1.1) * env(t, 0.002, tau))


def syllable(f0, f1, secs):
    """One giggle 'ha': a quick pitch-falling blip."""
    t = tv(secs)
    f = glide(f0, f1, t, secs)
    x = tone(f) + 0.3 * tone(f * 2.0)
    return taper(unit(x) * env(t, 0.006, secs * 0.45))


def brass(r, secs, f0, f1, form=(700.0, 1800.0), attack=0.03, release=0.1):
    """A brass or reed note gliding f0 -> f1 (Hz) through two formants: a trombone, a bugle, a horn."""
    t = tv(secs)
    v = voice(glide(f0, f1, t, secs), len(t), 24, 1.0, 0.002, 5.5, r)
    v = unit(svf(v, form[0], 1.6) + 0.5 * svf(v, form[1], 2.5))
    return taper(v * np.minimum(t / attack, 1.0) * np.clip((secs - t) / release, 0.0, 1.0))


def gen_emotes():
    # wave: a cheery two-note whistle, "ooo-wee"
    name = "emote_wave"
    r = rng(name)
    x = np.zeros(ns(dur(name)))
    place(x, 0.0, whistle(midi(76), midi(83), 0.36), 0.8)
    place(x, 0.4, whistle(midi(83), midi(88), 0.48), 0.8)
    save(name, x, fin=0.002, fout=0.12)

    # thumbs up: a bright double ding
    name = "emote_thumbsup"
    x = np.zeros(ns(dur(name)))
    place(x, 0.0, fm_glass(midi(84), 0.45, 0.2, 0.6), 0.8)
    place(x, 0.1, fm_glass(midi(91), 0.4, 0.18, 0.5), 0.6)
    save(name, x, fin=0.001, fout=0.1)

    # dance: a short funky groove - eight stepped bass plucks with hi-hat ticks and a bright lead
    name = "emote_dance"
    r = rng(name)
    x = np.zeros(ns(dur(name)))
    step = 0.175
    for k, m in enumerate((45, 45, 48, 50, 45, 52, 50, 48)):
        t0 = k * step
        place(x, t0, pluck(midi(m), 0.16), 0.9)
        place(x, t0 + step / 2, click(r, 0.04, 6000, 12000, 0.008), 0.25)
        if k % 2 == 1:
            place(x, t0 + step / 2, fm_glass(midi(m + 24), 0.16, 0.06, 0.8), 0.45)
    save(name, x, fin=0.002, fout=0.1)

    # bow: a soft swoosh and two chimes
    name = "emote_bow"
    r = rng(name)
    x = 0.6 * whoosh(r, dur(name), 250, 900, 300, 0.45, 0.2)
    place(x, 0.5, fm_glass(midi(79), 0.9, 0.35, 0.5), 0.7)
    place(x, 0.62, fm_glass(midi(86), 0.8, 0.3, 0.4), 0.45)
    save(name, x, fin=0.002, fout=0.2)

    # laugh: a bubbly giggle - six falling 'ha' blips, each with a bubble popping in
    name = "emote_laugh"
    r = rng(name)
    x = np.zeros(ns(dur(name)))
    for k in range(6):
        t0 = 0.02 + k * 0.18
        place(x, t0, syllable(midi(76 + (k % 2) * 2), midi(70 + (k % 2) * 2), 0.15), 0.7)
        place(x, t0 + 0.05, bubble(520.0 + 40.0 * k, 0.12, 0.02, 0.6), 0.25)
    save(name, x, fin=0.002, fout=0.15)

    # flex: a power-up whoomp - a low sweep rising with a rush of air and a bright glint
    name = "emote_flex"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    x = 0.8 * tone(glide(90.0, 280.0, t, 0.5)) * env(t, 0.01, 0.35)
    x += 0.35 * noise(r, n, 300, 3000) * env(t, 0.02, 0.3)
    place(x, 0.22, fm_glass(midi(79), 0.5, 0.25, 0.5), 0.5)
    save(name, x, fin=0.002, fout=0.12)

    # spin: a whirl - a tone swooping up and down, and two swishes
    name = "emote_spin"
    r = rng(name)
    t = tv(dur(name))
    x = 0.5 * tone(320.0 * 2.0 ** (2.0 * np.sin(np.pi * t / dur(name)))) * np.sin(np.pi * t / dur(name)) ** 0.7
    x += 0.6 * whoosh(r, dur(name), 400, 2000, 600, 0.45, 0.25)
    save(name, x, fin=0.002, fout=0.12)

    # facepalm: a slap, then a sad trombone - wah, wah, waaah
    name = "emote_facepalm"
    r = rng(name)
    x = np.zeros(ns(dur(name)))
    place(x, 0.0, click(r, 0.06, 800, 6000, 0.008), 1.0)
    place(x, 0.0, thud(tv(0.12), 260, 120, 0.02, 0.03, harm=(0.3, 0.1)), 0.9)
    place(x, 0.22, brass(r, 0.2, midi(62), midi(62), (500.0, 1100.0), 0.05, 0.08), 0.8)
    place(x, 0.44, brass(r, 0.2, midi(61), midi(61), (500.0, 1100.0), 0.05, 0.08), 0.8)
    place(x, 0.66, brass(r, 0.32, midi(59), midi(55), (500.0, 1100.0), 0.05, 0.15), 0.8)
    save(name, x, fin=0.001, fout=0.1)

    # taunt: a cheeky "nyah-nyah-nyaaah" warble, the pitch climbing as it goes
    name = "emote_taunt"
    r = rng(name)
    t = tv(dur(name))
    n = len(t)
    v = voice(glide(midi(60), midi(67), t, dur(name)) * (1.0 + 0.04 * np.sin(TAU * 9.0 * t)), n, 16, 1.2, 0.0, 5.0, r)
    v = unit(svf(v, 900.0, 2.5) + 0.6 * svf(v, 2200.0, 3.0))
    gate = 0.2 + 0.8 * np.abs(np.sin(np.pi * 3.0 * t))
    x = v * gate * np.minimum(t / 0.02, 1.0) * np.clip((dur(name) - t) / 0.1, 0.0, 1.0)
    save(name, x, fin=0.002, fout=0.12)

    # sit: a soft plop - a bubble dropping in and a low thump
    name = "emote_sit"
    r = rng(name)
    t = tv(dur(name))
    x = bubble(180.0, dur(name), 0.08, 1.2) + 0.5 * thud(t, 130, 60, 0.05, 0.05)
    x += 0.3 * click(r, dur(name), 200, 1500, 0.01)
    save(name, x, fin=0.001, fout=0.1)

    # strongman: a brass hit - a fat horn chord and a low thud
    name = "emote_strongman"
    r = rng(name)
    t = tv(dur(name))
    x = np.zeros(ns(dur(name)))
    place(x, 0.0, brass(r, 0.85, midi(45), midi(45), (500.0, 1200.0), 0.01, 0.25), 0.8)
    place(x, 0.0, brass(r, 0.85, midi(52), midi(52), (500.0, 1200.0), 0.01, 0.25), 0.55)
    place(x, 0.0, thud(t, 90, 40, 0.05, 0.12, harm=(0.4, 0.2)), 0.6)
    save(name, x, fin=0.001, fout=0.1)

    # salute: a bugle call - a short note, then a long one
    name = "emote_salute"
    r = rng(name)
    x = np.zeros(ns(dur(name)))
    place(x, 0.0, brass(r, 0.28, midi(67), midi(67), (900.0, 2200.0), 0.01, 0.05), 0.8)
    place(x, 0.3, brass(r, 0.65, midi(72), midi(72), (900.0, 2200.0), 0.01, 0.2), 0.8)
    save(name, x, fin=0.001, fout=0.1)

    # hero: a rising heroic sting - a horn arpeggio up to a held high note with a shimmer
    name = "emote_hero"
    r = rng(name)
    x = np.zeros(ns(dur(name)))
    for t0, m, d in ((0.0, 60, 0.2), (0.18, 64, 0.2), (0.36, 67, 0.2), (0.56, 72, 0.84)):
        place(x, t0, brass(r, d, midi(m), midi(m), (700.0, 1800.0), 0.02, 0.12), 0.8)
    place(x, 0.56, fm_glass(midi(84), 0.8, 0.4, 0.6), 0.3)
    save(name, x, fin=0.002, fout=0.12)

    # dab: a zippy swoosh with a snap at the end
    name = "emote_dab"
    r = rng(name)
    x = whoosh(r, dur(name), 500, 3500, 1000, 0.25, 0.1, q=2.0)
    place(x, 0.5, click(r, 0.04, 2000, 8000, 0.004), 0.5)
    save(name, x, fin=0.001, fout=0.08)

    # rock star: a distorted power chord (E2 B2 E3) with a pick attack
    name = "emote_rockstar"
    r = rng(name)
    n = ns(dur(name))
    t = tv(dur(name))
    chord = np.zeros(n)
    for m in (40, 47, 52):
        chord += buzz_wave(midi(m), n, 16, 1.0, 1.0)
    x = np.tanh(3.5 * unit(chord) * env(t, 0.003, 0.9))
    x = band(x, 80, 5000) + 0.4 * click(r, dur(name), 1500, 6000, 0.01)
    save(name, x, fin=0.001, fout=0.2)


# ===========================================================================
# verification
# ===========================================================================
# ===========================================================================
# the Big Update's three new worlds' mechanics: Toybox Tumble (gen_toybox), Olympus Rising (gen_olympus)
# and Pixel Panic (gen_arcade). Each clip is called by name from mechanics/<world>_*.gd.
# ===========================================================================
def xylo(r, f, secs):
    """A wooden xylophone bar struck with a hard mallet: a free bar's modes over a dry tick."""
    t = tv(secs)
    x = modes(t, bar_modes(f, 0.45, (1.0, 0.3, 0.12, 0.05, 0.02), 1.0), r, 0.002, hard=6000)
    return taper(x + 0.25 * click(r, secs, 2000, 8000, 0.002), 0.01)


def ratchet(r, secs, count, pw, lo, hi):
    """A toy ratchet: a pawl clicking over a toothed wheel. pw > 1 bunches the clicks up at the end
    (the key winding faster), pw < 1 spaces them out (the lift slowing as it tops out)."""
    x = np.zeros(ns(secs))
    for k in range(count):
        t0 = secs * 0.96 * (1.0 - (1.0 - k / count) ** pw)
        place(x, t0, click(r, 0.03, lo, hi, 0.0015), r.uniform(0.6, 1.0))
    return x


def stone_knock(r, secs, f0):
    """A block of stone landing on stone: a short low thud over a dry grit tick."""
    t = tv(secs)
    return taper(thud(t, f0, f0 * 0.45, 0.04, 0.05, harm=(0.4, 0.15)) + 0.4 * click(r, secs, 800, 4000, 0.004), 0.01)


def lyre(f, secs, tau=0.9):
    """A plucked golden lyre string: a bright pluck that dulls fast over a warm fundamental."""
    t = tv(secs)
    x = tone(f, t) + 0.35 * tone(f * 2.0, t) * np.exp(-t / 0.25) + 0.12 * tone(f * 3.0, t) * np.exp(-t / 0.1)
    return taper(x * env(t, 0.003, tau), 0.02)


def chip(f, n, wave="square"):
    """A chiptune voice following pitch f (scalar or per-sample): a band-limited square (odd harmonics,
    1/k) or triangle (odd harmonics, 1/k^2, alternating sign). Band-limited, so it never aliases."""
    f = np.broadcast_to(np.asarray(f, dtype=float), (n,))
    ph = TAU * np.cumsum(f) / SR
    top = float(np.max(f))
    x = np.zeros(n)
    for k in range(1, 200, 2):
        if top * k > SR * 0.42:
            break
        if wave == "tri":
            x += (-1.0) ** ((k - 1) // 2) * np.sin(k * ph) / (k * k)
        else:
            x += np.sin(k * ph) / k
    return unit(x)


def chip_note(f, secs, tau, wave="square", attack=0.002):
    """One chiptune note: an instant attack and an exponential decay."""
    t = tv(secs)
    return taper(chip(f, len(t), wave) * env(t, attack, tau), 0.005)


def bitcrush(x, bits=4):
    """Sample-depth crush: the grit of an old cartridge."""
    q = 2.0 ** (bits - 1)
    return np.round(x * q) / q


def gen_toybox():
    # the checkpoint: a music box runs up a C major arpeggio and tinkles the top note
    name = "toybox_checkpoint"
    r = rng(name)
    x = np.zeros(ns(dur(name)))
    for k, nt in enumerate((72, 76, 79, 84, 88)):
        place(x, 0.06 * k, tine(r, midi(nt), dur(name), 0.9), 0.8 if k < 4 else 0.6)
    save(name, x, fin=0.002, fout=0.15)

    # the finish: the toy rocket roars up while a music-box fanfare rings out over it
    name = "toybox_finish"
    r = rng(name)
    n = ns(dur(name))
    t = tv(dur(name))
    roar = noise(r, n, 120, 3500) * (0.25 + 0.75 * np.clip(t / 1.8, 0.0, 1.0)) * np.exp(-np.maximum(t - 2.4, 0.0) / 0.2)
    x = 0.8 * roar + 0.6 * thud(t, 60, 35, 1.2, 1.2, harm=(0.2, 0.05))
    x += 0.4 * whoosh(r, dur(name), 200, 1800, 500, 1.6, 0.4)
    for k, nt in enumerate((72, 76, 79, 84)):
        place(x, 0.05 + 0.13 * k, tine(r, midi(nt), 1.0, 1.0), 0.7)
    for nt in (84, 88, 91):
        place(x, 0.7, tine(r, midi(nt), 2.0, 1.4), 0.5)
    save(name, x, fin=0.002, fout=0.25)

    # the car's key: the ratchet clicks faster and faster as the spring tightens, a wind-up whine under it
    name = "toybox_car_wind"
    r = rng(name)
    t = tv(dur(name))
    x = ratchet(r, dur(name), 22, 1.8, 2000, 7000)
    x += 0.25 * tone(glide(260.0, 620.0, t, dur(name))) * np.minimum(t / 0.05, 1.0)
    save(name, x, fin=0.002, fout=0.08)

    # the car runs down: a tin clunk
    name = "toybox_car_stop"
    r = rng(name)
    t = tv(dur(name))
    x = thud(t, 260, 120, 0.02, 0.03, harm=(0.3, 0.1)) + 0.5 * modes(t, bar_modes(780.0, 0.08), r, 0.01, hard=4000)
    x += 0.4 * click(r, dur(name), 1500, 6000, 0.002)
    save(name, x, fin=0.0008, fout=0.08)

    # the car's clockwork (loop): a spring hum and 24 gear teeth ticking round each lap
    name = "toybox_car_whirr"
    r = rng(name)
    n = ns(dur(name))
    t = tv(dur(name))
    gear = np.zeros(n)
    for k in range(24):
        cplace(gear, k * dur(name) / 24.0, click(r, 0.012, 1500, 6000, 0.002), 0.6 + 0.4 * r.uniform())
    hum = tone(cyc(150.0, n), t) + 0.35 * tone(cyc(300.0, n), t)
    save_loop(name, 0.7 * unit(hum) * (0.7 + 0.3 * clfo(n, 24)) + 0.5 * unit(gear))

    # the jack-in-the-box tunes up: a music box plays a wobbling tune, the notes bunching up as it winds faster
    name = "toybox_jack_tune"
    r = rng(name)
    x = np.zeros(ns(dur(name)))
    t = tv(dur(name))
    notes = (72, 76, 79, 76, 81, 84, 81, 79, 84)
    for k, nt in enumerate(notes):
        t0 = dur(name) * (1.0 - (1.0 - k / len(notes)) ** 1.6)
        place(x, t0, tine(r, midi(nt) * (1.0 + 0.012 * np.sin(k * 1.3)), 0.6, 0.5), 0.8)
    x += 0.25 * tone(glide(300.0, 900.0, t, dur(name))) * np.clip(t / dur(name), 0.0, 1.0) ** 3
    save(name, x, fin=0.002, fout=0.05)

    # the pop: SPROING - the spring releases and the clown head bangs out of the box
    name = "toybox_jack_pop"
    r = rng(name)
    n = ns(dur(name))
    t = tv(dur(name))
    boing = tone(glide(160.0, 900.0, t, 0.2)) * env(t, 0.001, 0.14)
    boing *= 1.0 + 0.3 * np.sin(TAU * 42.0 * t) * np.exp(-t / 0.2)
    x = boing + 0.5 * noise(r, n, 1200, 5000) * env(t, 0.001, 0.05) + 0.7 * thud(t, 260, 90, 0.05, 0.06)
    save(name, x, fin=0.0005, fout=0.1)

    # one tick of the toy rattle (played once per tick, faster as the warning nears)
    name = "toybox_tell_tick"
    r = rng(name)
    t = tv(dur(name))
    x = click(r, dur(name), 2500, 8000, 0.0015) + 0.5 * modes(t, bar_modes(1400.0, 0.01), r, 0.01, hard=6000)
    save(name, x, fin=0.0005, fout=0.02)

    # the blocks groan under the strain: stacked timber and a couple of knocks
    name = "toybox_tower_creak"
    r = rng(name)
    x = creak(r, dur(name), lambda u: 12.0 + 26.0 * u, [(210.0, 1.0, 0.03), (520.0, 0.6, 0.02), (1100.0, 0.35, 0.012)])
    place(x, 0.3, wood_knock(r, 0.08, 330.0, 0.015, 4000.0), 0.35)
    place(x, 0.9, wood_knock(r, 0.08, 300.0, 0.015, 4000.0), 0.45)
    save(name, x, fin=0.002, fout=0.1)

    # the tower topples: a scatter of wooden blocks clattering down, denser at the start
    name = "toybox_tower_fall"
    r = rng(name)
    x = 0.5 * thud(tv(dur(name)), 140.0, 60.0, 0.1, 0.12)
    for t0 in np.sort(0.95 * dur(name) * r.random(18) ** 0.8):
        place(x, t0, wood_knock(r, 0.14, r.uniform(260.0, 640.0), 0.012, 4500.0), r.uniform(0.3, 0.9))
    save(name, x, fin=0.002, fout=0.1)

    # the tower slaps down across the gap: a heavy wooden slap
    name = "toybox_tower_thud"
    r = rng(name)
    n = ns(dur(name))
    t = tv(dur(name))
    x = thud(t, 110.0, 45.0, 0.06, 0.08) + 0.6 * wood_knock(r, dur(name), 230.0, 0.03, 4000.0)
    x += 0.4 * noise(r, n, 1000, 4000) * env(t, 0.001, 0.04)
    save(name, x, fin=0.0005, fout=0.1)

    # the blocks ratchet back up like a toy on a spring: slowing clicks and a rising whine
    name = "toybox_tower_lift"
    r = rng(name)
    t = tv(dur(name))
    x = ratchet(r, dur(name), 16, 0.6, 1500, 6000)
    x += 0.3 * tone(glide(220.0, 520.0, t, dur(name))) * np.clip(t / 0.1, 0.0, 1.0)
    save(name, x, fin=0.002, fout=0.08)

    # a music-box chime each beat of the last second
    name = "toybox_tower_chime"
    r = rng(name)
    x = np.zeros(ns(dur(name)))
    place(x, 0.0, tine(r, midi(84), dur(name), 1.0), 0.8)
    place(x, 0.1, tine(r, midi(91), dur(name), 0.8), 0.5)
    save(name, x, fin=0.001, fout=0.1)

    # five xylophone notes on the pentatonic scale, climbing (the key bounce)
    for k, nt in enumerate((72, 74, 76, 79, 81), start=1):
        name = "toybox_note_%d" % k
        r = rng(name)
        save(name, xylo(r, midi(nt), dur(name)), fin=0.0005, fout=0.08)


def gen_olympus():
    # the checkpoint: a golden lyre chord, strummed, with a glint of light
    name = "olympus_checkpoint"
    r = rng(name)
    x = np.zeros(ns(dur(name)))
    for k, nt in enumerate((64, 68, 71, 76)):
        place(x, 0.035 * k, lyre(midi(nt), dur(name) - 0.035 * k, 0.9), 0.6)
    place(x, 0.12, fm_glass(midi(88), 0.9, 0.3, 0.4), 0.25)
    save(name, x, fin=0.002, fout=0.15)

    # the finish: a brass and choir swell in the temple's reverb
    name = "olympus_finish"
    r = rng(name)
    n = ns(dur(name))
    t = tv(dur(name))
    brass = horn(r, dur(name), (52, 59, 64, 71), (700.0, 1800.0), 0.03, 0.35, 0.6)
    choir = voice(glide(midi(64), midi(67), t, dur(name)), n, 16, 1.2, 0.005, 5.0, r)
    choir = unit(svf(choir, 800.0, 2.0) + 0.5 * svf(choir, 1150.0, 3.0))
    swell = np.minimum(t / 0.9, 1.0) * np.clip((dur(name) - t) / 0.5, 0.0, 1.0)
    x = space(r, 0.8 * brass + 0.6 * choir * swell, 1.6, 0.2)
    save(name, x, fin=0.01, fout=0.2)

    # the chariot's wings (loop): beating feathers, four strokes a second, over a rush of air
    name = "olympus_chariot_wind"
    r = rng(name)
    n = ns(dur(name))
    flap = 0.3 + 0.7 * np.abs(clfo(n, 8))
    wings = cband(r.standard_normal(n), 400, 2600) * flap
    rush = cnoise(r, n, 90, 500)
    save_loop(name, unit(wings) + 0.5 * unit(rush))

    # the chariot leaves its dock: a rush of wings
    name = "olympus_chariot_launch"
    r = rng(name)
    x = whoosh(r, dur(name), 400.0, 2400.0, 800.0, 0.35, 0.3)
    for k in range(6):
        place(x, 0.04 + 0.09 * k, noise(r, ns(0.07), 900, 4000) * env(tv(0.07), 0.003, 0.03), 0.6 * (1.0 - k / 8.0))
    save(name, x, fin=0.002, fout=0.2)

    # the column's tell: old marble groans and splits, then a sharp crack
    name = "olympus_column_crack"
    r = rng(name)
    x = creak(r, dur(name), lambda u: 20.0 + 50.0 * u, [(320.0, 1.0, 0.02), (980.0, 0.6, 0.012), (1900.0, 0.35, 0.008)])
    place(x, 0.9, click(r, 0.05, 600, 6000, 0.008), 0.8)
    place(x, 0.9, stone_knock(r, 0.4, 200.0), 0.6)
    save(name, x, fin=0.002, fout=0.1)

    # the column tears loose and tumbles down through the clouds: a tearing rush and falling stone
    name = "olympus_column_fall"
    r = rng(name)
    n = ns(dur(name))
    t = tv(dur(name))
    tear = noise(r, n, 350, 3000) * (0.4 + 0.6 * np.abs(noise(r, n, None, 25))) * env(t, 0.02, 0.9)
    x = unit(tear)
    for k, t0 in enumerate((0.25, 0.48, 0.66, 0.9, 1.05, 1.2, 1.32, 1.42)):
        place(x, t0, stone_knock(r, 0.35, r.uniform(150.0, 260.0)), 0.9 * 0.8 ** k)
    save(name, x, fin=0.002, fout=0.15)

    # the column rises back out of the cloud: gold chimes
    name = "olympus_column_reform"
    r = rng(name)
    x = np.zeros(ns(dur(name)))
    for k, nt in enumerate((79, 83, 86, 91)):
        place(x, 0.16 * k, fm_glass(midi(nt), 1.0, 0.35, 0.6), 0.6 - 0.08 * k)
    save(name, x, fin=0.002, fout=0.2)

    # the mirror's charge: a rising chime and a glint of bright metal
    name = "olympus_mirror_charge"
    r = rng(name)
    t = tv(dur(name))
    f = glide(900.0, 2600.0, t, dur(name))
    x = taper(tone(f) * env(t, 0.25, 0.8) + 0.3 * tone(2.0 * f) * env(t, 0.25, 0.4), 0.02)
    place(x, 0.7, fm_glass(midi(96), 0.5, 0.15, 0.4), 0.5)
    save(name, x, fin=0.002, fout=0.08)

    # the mirror fires: a bright blade of light striking out across the court
    name = "olympus_mirror_fire"
    r = rng(name)
    t = tv(dur(name))
    x = whoosh(r, dur(name), 2000.0, 5000.0, 2500.0, 0.05, 0.05) * 0.8
    x += 0.6 * modes(t, bell_modes(1400.0, 0.45), r, 0.004)
    x += 0.4 * click(r, dur(name), 3000, 9000, 0.002)
    save(name, x, fin=0.0005, fout=0.12)

    # the mirror's light singing (loop): a steady E5 with its octave and fifth, breathing slowly
    name = "olympus_mirror_hum"
    n = ns(dur(name))
    t = tv(dur(name))
    f = cyc(midi(76), n)
    x = tone(f, t) + 0.35 * tone(2.0 * f, t) + 0.12 * tone(3.0 * f, t)
    save_loop(name, x * (0.85 + 0.15 * clfo(n, 5)))

    # the spirit draws breath upwind: a rising whistle with the air in it
    name = "olympus_spirit_call"
    r = rng(name)
    n = ns(dur(name))
    t = tv(dur(name))
    x = whistle(midi(62), midi(79), dur(name), 0.02) + 0.25 * noise(r, n, 1800, 5000) * np.clip(t / dur(name), 0.0, 1.0)
    save(name, x, fin=0.002, fout=0.1)

    # the gust sweeps the lane: a rushing gust
    name = "olympus_spirit_gust"
    r = rng(name)
    n = ns(dur(name))
    t = tv(dur(name))
    x = whoosh(r, dur(name), 200.0, 1400.0, 250.0, 0.55, 0.35) + 0.35 * noise(r, n, 300, 2000) * env(t, 0.3, 0.6)
    save(name, x, fin=0.002, fout=0.2)

    # one small bronze bell tick (played once per tick, faster as the hazard nears)
    name = "olympus_tell_tick"
    r = rng(name)
    t = tv(dur(name))
    x = modes(t, bell_modes(1046.5, 0.2), r, 0.003) + 0.15 * click(r, dur(name), 3000, 9000, 0.001)
    save(name, x, fin=0.0005, fout=0.05)

    # the wind along the lane (loop): steady air, swelling slowly
    name = "olympus_wind_loop"
    r = rng(name)
    n = ns(dur(name))
    body = cnoise(r, n, 120, 900) * (0.6 + 0.4 * crand(r, n, 4))
    save_loop(name, unit(body) + 0.5 * cnoise(r, n, 40, 180))


def gen_arcade():
    # the 1-up jingle: six quick square notes, then a held top note
    name = "arcade_checkpoint"
    x = np.zeros(ns(dur(name)))
    for k, nt in enumerate((76, 79, 88, 84, 86, 91)):
        place(x, 0.1 * k, chip_note(midi(nt), 0.2, 0.12), 0.7)
    place(x, 0.6, chip_note(midi(91), 0.6, 0.35), 0.7)
    save(name, x, fin=0.001, fout=0.15)

    # the stage-clear fanfare: a C arpeggio climbing to a held chord over a triangle bass
    name = "arcade_finish"
    x = np.zeros(ns(dur(name)))
    for k, nt in enumerate((72, 76, 79, 84)):
        place(x, 0.11 * k, chip_note(midi(nt), 0.2, 0.15), 0.6)
    for nt in (84, 88, 91):
        place(x, 0.5, chip_note(midi(nt), 1.8, 0.9), 0.45)
    place(x, 0.5, chip_note(midi(48), 2.2, 1.2, "tri"), 0.6)
    save(name, x, fin=0.001, fout=0.2)

    # the boss breaks into pixels: a noise explosion, then a falling-away minor arpeggio
    name = "arcade_boss_defeat"
    r = rng(name)
    n = ns(dur(name))
    t = tv(dur(name))
    x = 0.9 * bitcrush(unit(noise(r, n, 60, 5000) * env(t, 0.002, 0.3)), 4)
    for k, nt in enumerate((69, 72, 76, 81, 84, 88, 93)):
        place(x, 0.12 + 0.045 * k, chip_note(midi(nt), 0.12 if k < 6 else 0.5, 0.08 if k < 6 else 0.35), 0.5)
    save(name, x, fin=0.001, fout=0.2)

    # the block's blip as it drops a step
    name = "arcade_block_tick"
    save(name, chip_note(midi(88), dur(name), 0.03), fin=0.0005, fout=0.01)

    # the piece locks in: a dull 8-bit thunk
    name = "arcade_block_land"
    r = rng(name)
    t = tv(dur(name))
    x = chip(glide(220.0, 70.0, t, 0.15), len(t), "tri") * env(t, 0.001, 0.07)
    x += 0.3 * click(r, dur(name), 800, 3000, 0.003)
    save(name, x, fin=0.0005, fout=0.02)

    # the row is about to clear: a flashing warble
    name = "arcade_block_clear_warn"
    n = ns(dur(name))
    t = tv(dur(name))
    f = 660.0 + 150.0 * np.sin(TAU * 11.0 * t)
    x = chip(f, n) * (0.6 + 0.4 * np.sin(TAU * 14.0 * t)) * (0.6 + 0.4 * t / dur(name))
    save(name, x, fin=0.002, fout=0.1)

    # the row clears: a bright line-clear sweep
    name = "arcade_block_clear"
    t = tv(dur(name))
    x = chip(glide(300.0, 1800.0, t, 0.5), len(t)) * env(t, 0.003, 0.35)
    save(name, x, fin=0.001, fout=0.1)

    # the block falls away: a descending zip
    name = "arcade_block_drop"
    t = tv(dur(name))
    x = chip(glide(1500.0, 200.0, t, 0.45), len(t)) * env(t, 0.002, 0.3)
    save(name, x, fin=0.001, fout=0.05)

    # the pong paddle turns at the end of its lane: a "tok"
    name = "arcade_paddle_ping"
    save(name, chip_note(440.0, dur(name), 0.05), fin=0.0005, fout=0.01)

    # the pong ball hits a wall: a higher ping
    name = "arcade_ball_ping"
    save(name, chip_note(1760.0, dur(name), 0.04), fin=0.0005, fout=0.01)

    # the glitch tile warns it will hop: a bitcrushed static stutter, getting louder
    name = "arcade_glitch_warn"
    r = rng(name)
    n = ns(dur(name))
    t = tv(dur(name))
    steps = 20
    seg = np.minimum((t * steps).astype(int), steps - 1)
    fs = np.exp(r.uniform(np.log(300.0), np.log(2400.0), steps))
    gates = (r.uniform(0.0, 1.0, steps) > 0.3).astype(float)
    x = chip(fs[seg], n) * gates[seg] * (0.3 + 0.7 * t / dur(name))
    save(name, bitcrush(x, 3), fin=0.002, fout=0.05)

    # the glitch tile hops: a zap down the scale with a burst of static
    name = "arcade_glitch_hop"
    r = rng(name)
    n = ns(dur(name))
    t = tv(dur(name))
    x = chip(glide(2000.0, 180.0, t, 0.35), n) * env(t, 0.001, 0.2)
    x += 0.5 * noise(r, n, 2000, 8000) * env(t, 0.001, 0.04)
    save(name, bitcrush(x, 4), fin=0.0005, fout=0.05)

    # the screen jolts and the siren warns: four alarm blips
    name = "arcade_scroll_start"
    x = np.zeros(ns(dur(name)))
    for k in range(4):
        place(x, 0.22 * k, chip_note(880.0 if k % 2 == 0 else 660.0, 0.2, 0.12), 0.7)
    save(name, x, fin=0.001, fout=0.1)

    # the boss's eyes lock on: a rising square sweep
    name = "arcade_boss_charge"
    t = tv(dur(name))
    x = chip(glide(150.0, 1600.0, t, dur(name)), len(t)) * (0.5 + 0.5 * t / dur(name))
    save(name, x, fin=0.002, fout=0.1)

    # the boss's column slams down: a crunchy 8-bit boom
    name = "arcade_boss_blast"
    r = rng(name)
    n = ns(dur(name))
    t = tv(dur(name))
    boom = unit(noise(r, n, 60, 6000) * env(t, 0.001, 0.22))
    low = chip(glide(160.0, 40.0, t, 0.8), n) * env(t, 0.002, 0.3)
    save(name, bitcrush(0.8 * boom + low, 4), fin=0.0005, fout=0.05)

    # the chomper's "waka waka" (loop): two mouth-opening chomps a second
    name = "arcade_chomper_loop"
    x = np.zeros(ns(dur(name)))
    m = ns(0.26)
    t = tv(0.26)
    for t0 in (0.0, 0.5):
        cplace(x, t0, chip(glide(300.0, 650.0, t, 0.26), m) * env(t, 0.003, 0.1), 0.8)
    save_loop(name, x)

    # the pong ball's hum (loop): a quiet triangle tone on a whole number of cycles
    name = "arcade_ball_hum"
    n = ns(dur(name))
    save_loop(name, chip(cyc(330.0, n), n, "tri"))

    # the scroll wall's rumble (loop): a low static roar pulsing eight times a loop
    name = "arcade_scroll_rumble"
    r = rng(name)
    n = ns(dur(name))
    low = cnoise(r, n, 35, 160) * (0.7 + 0.3 * clfo(n, 8))
    save_loop(name, unit(low) + 0.4 * chip(cyc(55.0, n), n))


# ===========================================================================
# Castle Siege (gen_siege) and Mushroom Hollow (gen_fungal): the mechanics' clips. Each is called by name
# from mechanics/siege_*.gd, mechanics/fungal_*.gd, levels/level_32_siege.gd and levels/level_26_fungal.gd.
# ===========================================================================
def snare_roll(r, secs, count, pw=1.8, lo=1800.0, hi=7000.0):
    """A snare drum roll: taps that bunch up towards the end (pw > 1 quickens them)."""
    x = np.zeros(ns(secs))
    for k in range(count):
        t0 = secs * (1.0 - (1.0 - k / count) ** pw)
        place(x, t0, noise(r, ns(0.03), lo, hi) * np.exp(-tv(0.03) / 0.006), r.uniform(0.4, 0.9))
    return x


def gen_siege():
    # the trebuchet's arm lets go: a last creak of the timber, then the arm whips away on a whoosh
    name = "siege_boulder_launch"
    r = rng(name)
    x = np.zeros(ns(dur(name)))
    place(x, 0.0, creak(r, 0.3, lambda u: 40.0 - 20.0 * u, [(260.0, 1.0, 0.02), (640.0, 0.6, 0.012), (1300.0, 0.3, 0.008)]), 0.6)
    place(x, 0.2, whoosh(r, 0.6, 160.0, 1100.0, 300.0, 0.22, 0.12), 0.9)
    place(x, 0.2, click(r, 0.01, 1500, 6000, 0.002), 0.3)
    save(name, x, fin=0.001, fout=0.1)

    # the boulder's whistle: a rising, gritty air-whistle over about 1.1 s
    name = "siege_boulder_whistle"
    r = rng(name)
    n = ns(dur(name))
    t = tv(dur(name))
    f = glide(520.0, 2300.0, t, dur(name))
    air = unit(svf(r.standard_normal(n), f, 12.0))
    x = 0.6 * unit(tone(f)) + 0.5 * air
    x *= np.minimum(t / 0.12, 1.0) * np.clip((dur(name) - t) / 0.15, 0.0, 1.0)
    save(name, x, fin=0.001, fout=0.05)

    # the boulder lands on the masonry: a heavy stone knock, a crack of grit and a spray of rubble
    name = "siege_boulder_impact"
    r = rng(name)
    n = ns(dur(name))
    t = tv(dur(name))
    body = thud(t, 120.0, 42.0, 0.12, 0.09, harm=(0.3, 0.1))
    rubble = np.zeros(n)
    grains(r, rubble, 28, 0.04, 0.55, 500.0, 3200.0, 0.003, 0.012, 1.0, decay=0.2)
    x = body + 0.8 * click(r, dur(name), 900, 5000, 0.004) + 0.5 * noise(r, n, 400, 2500) * env(t, 0.001, 0.05)
    x += 0.6 * unit(rubble)
    save(name, x, fin=0.0008, fout=0.12)

    # the ram's chains take the strain: a groan of iron with link rattles through it
    name = "siege_ram_creak"
    r = rng(name)
    n = ns(dur(name))
    x = iron_creak(r, dur(name), 210.0, rate=(14.0, 30.0))
    rattle = np.zeros(n)
    for _ in range(14):
        t0 = r.uniform(0.0, dur(name) * 0.9)
        place(rattle, t0, modes(tv(0.05), bar_modes(r.uniform(900.0, 1500.0), 0.012, (1.0, 0.5, 0.3, 0.15, 0.1), 0.8),
                                r, 0.02, hard=4000), r.uniform(0.3, 0.8))
    x += 0.6 * unit(rattle)
    save(name, x, fin=0.002, fout=0.1)

    # the log swings in on its chains: an air whoosh with a low body under it
    name = "siege_ram_whoosh"
    r = rng(name)
    n = ns(dur(name))
    t = tv(dur(name))
    x = whoosh(r, dur(name), 110.0, 420.0, 130.0, 0.38, 0.22, 1.4)
    x += 0.25 * noise(r, n, 60, 300) * np.sin(np.pi * np.clip(t / dur(name), 0.0, 1.0)) ** 0.8
    save(name, x, fin=0.002, fout=0.08)

    # the log strikes the gate: a heavy wooden thud
    name = "siege_ram_thud"
    r = rng(name)
    n = ns(dur(name))
    t = tv(dur(name))
    body = thud(t, 95.0, 38.0, 0.09, 0.11, harm=(0.35, 0.12))
    x = body + 0.5 * wood_knock(r, dur(name), 150.0, 0.05, 2500.0) + 0.35 * noise(r, n, 80, 700) * env(t, 0.002, 0.05)
    save(name, x, fin=0.0008, fout=0.12)

    # the cauldron tips on its trunnions: an iron groan that swells and dies away
    name = "siege_oil_tilt"
    r = rng(name)
    t = tv(dur(name))
    x = iron_creak(r, dur(name), 130.0, rate=(8.0, 18.0)) + 0.35 * thud(t, 80.0, 55.0, 0.5, 0.6, harm=(0.2,))
    save(name, x, fin=0.002, fout=0.1)

    # the oil pours out in a thick gout: broad wet noise under a crowd of bubbles
    name = "siege_oil_pour"
    r = rng(name)
    n = ns(dur(name))
    t = tv(dur(name))
    x = 0.8 * noise(r, n, 200, 1600) * env(t, 0.03, 0.5)
    for _ in range(20):
        t0 = r.uniform(0.05, 0.9)
        place(x, t0, bubble(r.uniform(260.0, 620.0), 0.07, r.uniform(0.012, 0.03), 0.9), r.uniform(0.2, 0.6))
    save(name, x, fin=0.002, fout=0.1)

    # the oil running down the gutter (loop): a steady rush of liquid, with bubbles rising through it
    name = "siege_oil_loop"
    r = rng(name)
    n = ns(dur(name))
    flow = cnoise(r, n, 220.0, 1700.0, 2) * (0.6 + 0.4 * crand(r, n, 5))
    gurgle = np.zeros(n)
    for _ in range(12):
        cplace(gurgle, r.uniform(0.0, dur(name)), bubble(r.uniform(300.0, 700.0), 0.08, r.uniform(0.008, 0.02), 0.7),
               r.uniform(0.15, 0.5))
    save_loop(name, unit(flow) + 0.6 * unit(gurgle) + 0.25 * cnoise(r, n, 60, 240))

    # the war horn: two low notes, a fifth apart, with a rasp
    name = "siege_volley_horn"
    r = rng(name)
    n = ns(dur(name))
    t = tv(dur(name))
    x = horn(r, dur(name), (43, 50), form=(600.0, 1400.0), scoop=0.05, attack=0.05, release=0.25)
    x += 0.2 * noise(r, n, 1500, 4000) * env(t, 0.05, 0.5)
    save(name, x, fin=0.002, fout=0.1)

    # the volley: a hiss of arrows through the air, rising and passing
    name = "siege_volley_whoosh"
    r = rng(name)
    n = ns(dur(name))
    t = tv(dur(name))
    x = 0.9 * whoosh(r, dur(name), 900.0, 2600.0, 1400.0, 0.5, 0.3, 1.2)
    hiss = noise(r, n, 2500, 9000) * (0.5 + 0.5 * np.sin(TAU * 9.0 * t)) * np.sin(np.pi * np.clip(t / dur(name), 0.0, 1.0)) ** 0.6
    x += 0.35 * hiss
    save(name, x, fin=0.002, fout=0.1)

    # the arrows bite the stone: a scatter of shaft thunks and a masonry tap under them
    name = "siege_volley_hit"
    r = rng(name)
    n = ns(dur(name))
    t = tv(dur(name))
    x = 0.8 * thud(t, 240.0, 110.0, 0.03, 0.03, harm=(0.2,)) + 0.4 * click(r, dur(name), 2000, 9000, 0.002)
    for _ in range(16):
        place(x, r.uniform(0.0, 0.55), wood_knock(r, 0.05, r.uniform(900.0, 1500.0), 0.008, 7000.0), r.uniform(0.3, 0.8))
    save(name, x, fin=0.0008, fout=0.08)

    # the winch takes up the arm: a ratchet clicking evenly round the drum, a timber under strain
    name = "siege_trebuchet_wind"
    r = rng(name)
    x = ratchet(r, dur(name), 30, 1.0, 1800.0, 6500.0)
    x += 0.35 * creak(r, dur(name), lambda u: 18.0, [(210.0, 1.0, 0.02), (460.0, 0.5, 0.012)])
    save(name, x, fin=0.002, fout=0.08)

    # the arm whips over and stops against its bar: a whoosh, a creak and a wooden knock
    name = "siege_trebuchet_throw"
    r = rng(name)
    x = whoosh(r, dur(name), 90.0, 520.0, 160.0, 0.45, 0.2, 1.8)
    place(x, 0.0, creak(r, 0.35, lambda u: 30.0, [(260.0, 1.0, 0.02), (600.0, 0.6, 0.012)]), 0.6)
    place(x, 0.45, wood_knock(r, 0.2, 180.0, 0.03, 3500.0), 0.9)
    save(name, x, fin=0.002, fout=0.1)

    # a short blast on the horn, two notes, with a warning rasp
    name = "siege_warning_horn"
    r = rng(name)
    n = ns(dur(name))
    t = tv(dur(name))
    x = horn(r, dur(name), (50, 57), form=(650.0, 1500.0), scoop=0.06, attack=0.02, release=0.12)
    x += 0.15 * noise(r, n, 1500, 4000) * env(t, 0.02, 0.2)
    save(name, x, fin=0.002, fout=0.08)

    # a stage banked: a horn call over a snare roll that quickens, and a shower of embers
    name = "siege_checkpoint"
    r = rng(name)
    n = ns(dur(name))
    x = np.zeros(n)
    place(x, 0.0, snare_roll(r, dur(name) * 0.7, 36, 1.8), 1.0)
    place(x, 0.3, horn(r, 1.7, (48, 55, 60), form=(700.0, 1800.0), scoop=0.04, attack=0.03, release=0.2), 0.7)
    embers = np.zeros(n)
    grains(r, embers, 30, 0.2, 1.8, 2000.0, 7000.0, 0.001, 0.003, 0.8, decay=0.6)
    x += 0.3 * unit(embers)
    save(name, x, fin=0.002, fout=0.2)

    # the banner is raised: a brass fanfare, drums and the army's roar
    name = "siege_finish"
    r = rng(name)
    n = ns(dur(name))
    t = tv(dur(name))
    x = np.zeros(n)
    for m, t0, d in ((55, 0.0, 0.4), (60, 0.4, 0.4), (64, 0.8, 0.4), (67, 1.2, 1.8)):
        place(x, t0, brass(r, d, midi(m), midi(m), (700.0, 1800.0), 0.02, 0.1), 0.5)
    for t0 in (0.0, 0.4, 0.8, 1.2, 1.6, 2.0):
        place(x, t0, thud(tv(0.3), 110.0, 45.0, 0.05, 0.09), 0.6)
    place(x, 1.6, snare_roll(r, 1.0, 26, 1.6), 0.5)
    crowd = noise(r, n, 250, 3000) * np.clip(t / 1.2, 0.0, 1.0) ** 1.2 * np.exp(-np.maximum(t - 2.4, 0.0) / 0.2)
    x += 0.35 * crowd
    save(name, x, fin=0.002, fout=0.25)


def gen_fungal():
    # the bounce: a rubbery boing as the cap springs, the boing wobbling as it settles
    name = "fungal_cap_boing"
    r = rng(name)
    t = tv(dur(name))
    boing = tone(glide(170.0, 520.0, t, 0.2)) * env(t, 0.001, 0.16)
    boing *= 1.0 + 0.25 * np.sin(TAU * 36.0 * t) * np.exp(-t / 0.18)
    x = unit(boing) + 0.35 * thud(t, 210.0, 95.0, 0.05, 0.05)
    save(name, x, fin=0.001, fout=0.08)

    # the checkpoint: a warm wooden chime, four xylophone notes up and one more above
    name = "fungal_checkpoint"
    r = rng(name)
    x = np.zeros(ns(dur(name)))
    for k, nt in enumerate((67, 71, 74, 79)):
        place(x, 0.07 * k, xylo(r, midi(nt), dur(name) - 0.07 * k), 0.7)
    place(x, 0.3, xylo(r, midi(86), dur(name) - 0.3), 0.45)
    save(name, x, fin=0.002, fout=0.15)

    # the finish: a rising chime of glass tines, with a soft puff of spores at the top
    name = "fungal_finish"
    r = rng(name)
    x = np.zeros(ns(dur(name)))
    for k, nt in enumerate((64, 67, 71, 74, 79, 83)):
        place(x, 0.12 * k, tine(r, midi(nt), 1.6, 1.0), 0.55)
    tt = tv(0.9)
    place(x, 0.7, taper(noise(r, len(tt), 200, 1400) * env(tt, 0.08, 0.3), 0.02), 0.6)
    save(name, x, fin=0.002, fout=0.25)

    # a drip lands in a puddle: a glassy tick
    name = "fungal_drip_plink"
    r = rng(name)
    x = fm_glass(midi(100), dur(name), 0.09, index=1.2, ratio=2.76, attack=0.001)
    x += 0.3 * click(r, dur(name), 3000, 9000, 0.0015)
    save(name, x, fin=0.0005, fout=0.03)

    # the drop lands on a leaf: a wet slap, a bubble and a few droplets flicking off
    name = "fungal_drip_splash"
    r = rng(name)
    n = ns(dur(name))
    t = tv(dur(name))
    drops = np.zeros(n)
    grains(r, drops, 14, 0.03, 0.35, 1200.0, 5000.0, 0.002, 0.006, 0.9, decay=0.15)
    x = 0.7 * thud(t, 260.0, 110.0, 0.05, 0.05, harm=(0.2,)) + 0.8 * noise(r, n, 600, 4000) * env(t, 0.0008, 0.035)
    x += 0.5 * unit(drops)
    place(x, 0.12, bubble(520.0, 0.12, 0.02, 0.6), 0.25)
    save(name, x, fin=0.0008, fout=0.08)

    # the puff inflates: a rising hiss that swells over about 1.1 s
    name = "fungal_puff_swell"
    r = rng(name)
    n = ns(dur(name))
    t = tv(dur(name))
    rise = np.clip(t / dur(name), 0.0, 1.0) ** 1.6
    hiss = svf(r.standard_normal(n), glide(320.0, 2400.0, t, dur(name)), 3.5)
    x = unit(hiss) * rise + 0.2 * tone(glide(300.0, 700.0, t, dur(name))) * rise
    save(name, x, fin=0.002, fout=0.08)

    # the puff lets out its breath: a soft whump
    name = "fungal_puff_blow"
    r = rng(name)
    n = ns(dur(name))
    t = tv(dur(name))
    x = thud(t, 170.0, 70.0, 0.06, 0.08, harm=(0.2,)) + 0.4 * noise(r, n, 200, 1200) * env(t, 0.002, 0.1)
    save(name, x, fin=0.001, fout=0.05)

    # one quick wooden tick of the warning toadstool (played once per tick, faster as the hazard nears)
    name = "fungal_tell_tick"
    r = rng(name)
    t = tv(dur(name))
    x = wood_knock(r, dur(name), 1250.0, 0.008, 7000.0) + 0.3 * click(r, dur(name), 2000, 7000, 0.001)
    save(name, x, fin=0.0003, fout=0.02)

    # the frog's croak: a buzzy, pulsed call that dips in pitch, through a throaty formant
    name = "fungal_frog_croak"
    r = rng(name)
    n = ns(dur(name))
    t = tv(dur(name))
    f = glide(160.0, 105.0, t, dur(name))
    car = sum(tone(f * k) / k ** 1.2 for k in range(1, 9))
    pulses = (0.5 - 0.5 * np.cos(TAU * 27.0 * t)) ** 2
    swell = np.sin(np.pi * np.clip(t / dur(name), 0.0, 1.0)) ** 0.5
    x = unit(svf(car, 600.0, 2.2) + 0.3 * car) * pulses * swell
    save(name, x, fin=0.002, fout=0.06)

    # the spores drift through the air (loop): an airy rush, swelling and easing
    name = "fungal_puff_loop"
    r = rng(name)
    n = ns(dur(name))
    body = cnoise(r, n, 300.0, 2600.0, 2) * (0.55 + 0.45 * crand(r, n, 4))
    save_loop(name, unit(body) + 0.3 * cnoise(r, n, 80, 300))

    # the snail trundles (loop): a wet bed under three soft squelches a loop, each one a suck of mud
    name = "fungal_snail_squelch"
    r = rng(name)
    n = ns(dur(name))
    bed = cnoise(r, n, 200.0, 900.0, 2) * (0.5 + 0.5 * clfo(n, 3))
    sq = np.zeros(n)
    for k in range(3):
        tt = tv(0.6)
        squelch = unit(svf(r.standard_normal(len(tt)), glide(350.0, 1100.0, tt, 0.6), 4.0))
        cplace(sq, k * dur(name) / 3.0, squelch * np.sin(np.pi * np.minimum(tt / 0.6, 1.0)) ** 2, 0.7)
    save_loop(name, unit(bed) + 0.8 * unit(sq))


def verify():
    ok = True
    total = 0
    print("verify:")
    for name, (want, loop) in CLIPS.items():
        path = os.path.join(OUT, name + ".wav")
        if not os.path.exists(path):
            print("  %-24s MISSING" % name)
            ok = False
            continue
        x, sr, sw = ga.read_wav(name)
        total += os.path.getsize(path)
        mono = x.shape[1] == 1
        x = x[:, 0]
        dur = len(x) / sr
        peak = ga.db(np.max(np.abs(x)))
        target = levelled_target(name)
        if target is None:
            level_ok = abs(peak - PEAK_DB) < 0.2
        else:
            # loudness-matched: on target, or held at the -3 dBFS peak when it can't get there
            level_ok = peak < PEAK_DB + 0.05 and (abs(loudness(x) - target) < 0.5 or abs(peak - PEAK_DB) < 0.2)
        good = (sr == SR and sw == 2 and mono and abs(dur - want) < 0.002 and level_ok and
                bool(np.all(np.isfinite(x))))
        if loop:
            # the step across the wrap must look like any other step, and so must the curvature
            steps = np.abs(np.diff(x))
            p999 = np.quantile(steps, 0.999)
            wrap = abs(x[0] - x[-1])
            c999 = np.quantile(np.abs(np.diff(x, n=2)), 0.999)
            seam_curv = np.max(np.abs(np.diff(np.concatenate([x[-3:], x[:3]]), n=2)))
            # and no dip or swell at the seam: the 40 ms window across the wrap must be as loud
            # as the windows elsewhere in the loop (a faded end would be the quietest by far)
            k = int(0.04 * sr)
            hop = int(0.01 * sr)
            xx = np.concatenate([x, x[:k]])
            rms = np.array([np.sqrt(np.mean(xx[i:i + k] ** 2)) for i in range(0, len(x), hop)])
            seam_rms = np.sqrt(np.mean(np.concatenate([x[-k // 2:], x[:k // 2]]) ** 2))
            lvl = ga.db(seam_rms) - ga.db(np.quantile(rms, 0.05))
            good = good and wrap <= p999 * 1.5 and seam_curv <= c999 * 1.5 and lvl > -3.0
            note = "loop: wrap %.4f (p99.9 %.4f) curv %.4f (p99.9 %.4f) seam %+.1f dB vs p5" % (
                wrap, p999, seam_curv, c999, lvl)
        else:
            edge = max(abs(x[0]), abs(x[-1]))
            good = good and edge < 0.002
            note = "edge %.5f" % edge
        ok &= bool(good)
        print("  %-24s %5.2f s peak %6.2f dB %s %s" % (name, dur, peak, note, "ok" if good else "FAIL"))
    print("  %d clips, total size %.2f MB %s" % (len(CLIPS), total / 1e6, "ok" if total < SIZE_BUDGET else "FAIL"))
    ok &= total < SIZE_BUDGET
    print("RESULT: " + ("ALL OK" if ok else "PROBLEMS FOUND"))
    return ok


GENERATORS = (gen_steps, gen_wall, gen_movement_loops, gen_lasers, gen_crusher_piston, gen_swings, gen_surfaces,
              gen_foundry, gen_reef, gen_orbital, gen_clockwork, gen_balance, gen_gardens, gen_ascent, gen_xeno,
              gen_volcano, gen_glacier, gen_desert, gen_manor, gen_armada, gen_candy, gen_carrier,
              gen_sakura, gen_jungle, gen_frontier, gen_neon, gen_doom, gen_abyss, gen_tempest, gen_void, gen_kit, gen_emotes,
              gen_toybox, gen_olympus, gen_arcade, gen_siege, gen_fungal)


def main():
    """--only=manor,armada runs just those generators (gen_<name>) before verifying everything.
    --themes=toybox,fungal re-renders just those surfaces' footsteps and landings (gen_steps) and then verifies."""
    global STEP_THEMES
    args = sys.argv[1:]
    only = [a.split("=", 1)[1].split(",") for a in args if a.startswith("--only=")]
    only = ["gen_" + o for o in only[0]] if only else None
    themes = [a.split("=", 1)[1] for a in args if a.startswith("--themes=")]
    if themes:
        STEP_THEMES = set(themes[0].split(","))
        only = ["gen_steps"]
    if "--verify" not in args:
        print("world effects -> audio/")
        for fn in GENERATORS:
            if only is None or fn.__name__ in only:
                fn()
        missing = [n for n in CLIPS if n not in LOG]
        if missing and only is None:
            print("not generated: " + ", ".join(missing))
            sys.exit(1)
    sys.exit(0 if verify() else 1)


if __name__ == "__main__":
    main()
