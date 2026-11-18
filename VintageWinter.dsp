declare name "Vintage Winter";
declare description "BPM-Synced Room Reverb with Vintage Frost & Color";
declare author "Producer & DeepSongwriter";
declare version "1.0";

import("stdfaust.lib");

bpm = vslider("[0]TEMPO/BPM [style:knob]", 120, 60, 190, 1);
room_size = vslider("[1]REVERB/Room Size [style:radio{'Klein':0;'Gross':1}]", 1, 0, 1, 1);
predelay_zero = checkbox("[1]REVERB/Predelay 0ms");
decay_scale = vslider("[1]REVERB/Decay Scale (%) [style:knob]", 100, 20, 200, 1) * 0.01;

low_cut = vslider("[2]TONE/Low Cut (Hz) [style:knob]", 100, 20, 1000, 1);
high_cut = vslider("[2]TONE/High Cut (Hz) [style:knob]", 8000, 1000, 20000, 10);

downsample = vslider("[3]VINTAGE/Downsample [style:knob]", 1, 1, 16, 1) : int;
age = vslider("[3]VINTAGE/Age (%) [style:knob]", 30, 0, 100, 1) * 0.01;

mix = vslider("[4]MASTER/Mix (%) [style:knob]", 35, 0, 100, 1) * 0.01;
out_gain = vslider("[4]MASTER/Output (dB) [style:knob]", 0, -24, 12, 0.1) : ba.db2linear;

predelay_ms = ba.if(predelay_zero, 0.0, 1875.0 / bpm);
predelay_samples = int(predelay_ms * 0.001 * ma.SR);

base_decay_ms = ba.if(room_size == 1, 240000.0 / bpm, 120000.0 / bpm);
target_t60 = max(0.15, base_decay_ms * 0.001 * decay_scale);
fb = min(0.94, max(0.35, 1.0 - (0.16 / target_t60)));
damp = min(0.85, max(0.1, 0.2 + age * 0.5));

comb_filter(del_samples, feedback, x) = loop ~ _
with {
    loop(y) = de.delay(4096, del_samples, x + y * (1.0 - damp) * feedback);
};

allpass(del_samples, x) = (+ : de.delay(2048, del_samples)) ~ (*(-0.5)) : *(0.5) + x;

age_lfo = os.osc(0.8) * 0.0008 * age;
frost_noise = no.noise * 0.0015 * age : fi.lowpass(1, 2500);

sample_hold(factor, x) = loop ~ _
with {
    trig = ba.pulse(factor);
    loop(y) = ba.if(trig, x, y);
};

reverb_tank(xL, xR) = (diffL, diffR)
with {
    sr_scale = ma.SR / 44100.0;
    preL = de.delay(65536, predelay_samples, xL) * (1.0 + age_lfo) + frost_noise;
    preR = de.delay(65536, predelay_samples, xR) * (1.0 - age_lfo) + frost_noise;

    cL = (comb_filter(int(1116 * sr_scale), fb, preL) +
          comb_filter(int(1188 * sr_scale), fb * 0.98, preL) +
          comb_filter(int(1277 * sr_scale), fb * 0.96, preL) +
          comb_filter(int(1356 * sr_scale), fb * 0.94, preL)) * 0.25;

    cR = (comb_filter(int(1139 * sr_scale), fb, preR) +
          comb_filter(int(1211 * sr_scale), fb * 0.98, preR) +
          comb_filter(int(1294 * sr_scale), fb * 0.96, preR) +
          comb_filter(int(1380 * sr_scale), fb * 0.94, preR)) * 0.25;

    diffL = cL : allpass(int(556 * sr_scale)) : allpass(int(441 * sr_scale));
    diffR = cR : allpass(int(579 * sr_scale)) : allpass(int(425 * sr_scale));
};

process(inL, inR) = (outL, outR)
with {
    reverbL, reverbR = reverb_tank(inL, inR);
    dsL = sample_hold(downsample, reverbL);
    dsR = sample_hold(downsample, reverbR);
    wetL = dsL : fi.highpass(2, low_cut) : fi.lowpass(2, high_cut);
    wetR = dsR : fi.highpass(2, low_cut) : fi.lowpass(2, high_cut);
    outL = (inL * (1.0 - mix) + wetL * mix) * out_gain;
    outR = (inR * (1.0 - mix) + wetR * mix) * out_gain;
};
