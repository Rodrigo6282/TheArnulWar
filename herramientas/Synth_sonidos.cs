using System;
using System.IO;

public class Biquad {
    double b0, b1, b2, a1, a2, x1, x2, y1, y2;
    public static Biquad BandPass(double f, double q, double sr) { var b = new Biquad(); b.SetBP(f, q, sr); return b; }
    public static Biquad LowPass(double f, double q, double sr) {
        var b = new Biquad(); double w = 2 * Math.PI * f / sr, al = Math.Sin(w) / (2 * q), c = Math.Cos(w), a0 = 1 + al;
        b.b0 = (1 - c) / 2 / a0; b.b1 = (1 - c) / a0; b.b2 = (1 - c) / 2 / a0; b.a1 = -2 * c / a0; b.a2 = (1 - al) / a0; return b;
    }
    public static Biquad HighPass(double f, double q, double sr) {
        var b = new Biquad(); double w = 2 * Math.PI * f / sr, al = Math.Sin(w) / (2 * q), c = Math.Cos(w), a0 = 1 + al;
        b.b0 = (1 + c) / 2 / a0; b.b1 = -(1 + c) / a0; b.b2 = (1 + c) / 2 / a0; b.a1 = -2 * c / a0; b.a2 = (1 - al) / a0; return b;
    }
    public void SetBP(double f, double q, double sr) {
        double w = 2 * Math.PI * f / sr, al = Math.Sin(w) / (2 * q), c = Math.Cos(w), a0 = 1 + al;
        b0 = al / a0; b1 = 0; b2 = -al / a0; a1 = -2 * c / a0; a2 = (1 - al) / a0;
    }
    public double P(double x) {
        double y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2;
        x2 = x1; x1 = x; y2 = y1; y1 = y; return y;
    }
}

public static class Synth {
    const int SR = 44100;
    static Random R;
    static double Rnd() { return R.NextDouble() * 2 - 1; }
    static double Rf(double a, double b) { return a + R.NextDouble() * (b - a); }

    static void Save(string path, double[] s, double peak) {
        double m = 1e-9;
        foreach (var v in s) m = Math.Max(m, Math.Abs(v));
        // short fade in/out to avoid clicks
        int fi = Math.Min(64, s.Length / 4), fo = Math.Min(400, s.Length / 4);
        for (int i = 0; i < fi; i++) s[i] *= (double)i / fi;
        for (int i = 0; i < fo; i++) s[s.Length - 1 - i] *= (double)i / fo;
        using (var w = new BinaryWriter(File.Create(path))) {
            int n = s.Length;
            w.Write(new char[] { 'R', 'I', 'F', 'F' }); w.Write(36 + n * 2);
            w.Write(new char[] { 'W', 'A', 'V', 'E', 'f', 'm', 't', ' ' }); w.Write(16);
            w.Write((short)1); w.Write((short)1); w.Write(SR); w.Write(SR * 2); w.Write((short)2); w.Write((short)16);
            w.Write(new char[] { 'd', 'a', 't', 'a' }); w.Write(n * 2);
            foreach (var v in s) w.Write((short)Math.Round(Math.Max(-1, Math.Min(1, v / m * peak)) * 32767));
        }
    }

    // ------------------------------------------------------------------ footsteps
    // boot on packed dirt/gravel: soft low heel thud, gravel crunch grains, then toe roll + scuff.
    static double[] Step(int seed, double heavy) {
        R = new Random(seed);
        int n = (int)(SR * (0.30 + heavy * 0.12));
        var o = new double[n];
        var lpT = Biquad.LowPass(260 + heavy * 40, 0.7, SR);
        var lpT2 = Biquad.LowPass(260, 0.7, SR);
        var bpC = Biquad.BandPass(Rf(1800, 2600), 0.9, SR);
        var bpC2 = Biquad.BandPass(Rf(3800, 5200), 1.2, SR);
        var hp = Biquad.HighPass(55, 0.7, SR);
        double toe = Rf(0.055, 0.085) + heavy * 0.02;
        double f0 = Rf(70, 95) - heavy * 15;
        double ph = 0;
        double grains = 0;
        for (int i = 0; i < n; i++) {
            double t = (double)i / SR;
            // heel thud: pitched-down sine + low noise
            double eH = Math.Exp(-t / (0.018 + heavy * 0.02)) * (1 - Math.Exp(-t / 0.0015));
            ph += 2 * Math.PI * f0 * (1 + 0.6 * Math.Exp(-t / 0.01)) / SR;
            double heel = Math.Sin(ph) * eH * (0.9 + heavy * 0.6) + lpT.P(Rnd()) * eH * 2.2;
            // toe: smaller second thud
            double tt = t - toe;
            double toeS = 0;
            if (tt > 0) {
                double eT = Math.Exp(-tt / 0.014) * (1 - Math.Exp(-tt / 0.002));
                toeS = lpT2.P(Rnd()) * eT * 1.3;
            }
            // gravel: sparse random grains, denser right after each contact
            double dens = 0.012 * Math.Exp(-t / 0.05) + (tt > 0 ? 0.01 * Math.Exp(-tt / 0.06) : 0) + 0.0008;
            if (R.NextDouble() < dens) grains += Rf(0.4, 1.0) * (R.NextDouble() < 0.5 ? -1 : 1);
            grains *= 0.86;
            double crunch = bpC.P(grains + Rnd() * 0.05) * 1.6 + bpC2.P(grains) * 0.6;
            // scuff: soft filtered noise sweep at the end of the roll
            double sc = 0;
            double ts = t - toe - 0.02;
            if (ts > 0) sc = bpC.P(Rnd()) * 0.15 * Math.Exp(-ts / 0.05) * (1 - Math.Exp(-ts / 0.01));
            o[i] = hp.P(heel * 1.0 + toeS + crunch * 0.55 + sc);
        }
        return o;
    }

    // ------------------------------------------------------------------ zombie voice
    // glottal pulse train (jitter, shimmer, creaky subharmonic) through 4 formant filters,
    // breath noise, wet gurgle AM and soft saturation.
    static double[] Voice(int seed, double dur, double[] f0Curve, double[][] vowels, double creak, double noise, double grit, double gurgle, double attack) {
        R = new Random(seed);
        int n = (int)(SR * dur);
        var o = new double[n];
        var F = new Biquad[4];
        for (int k = 0; k < 4; k++) F[k] = Biquad.BandPass(500, 5, SR);
        double[] gains = { 1.0, 0.6, 0.28, 0.12 };
        var lpB = Biquad.LowPass(2500, 0.7, SR);
        var hp = Biquad.HighPass(70, 0.7, SR);
        var lpO = Biquad.LowPass(5200, 0.7, SR);
        double ph = 0, jit = 0, sh = 1, gur = 0, gurT = 0, gurA = 0;
        int period = 0;
        for (int i = 0; i < n; i++) {
            double t = (double)i / n;
            double ts = (double)i / SR;
            // pitch curve (piecewise linear over the control points)
            double pos = t * (f0Curve.Length - 1);
            int a = Math.Min((int)pos, f0Curve.Length - 2);
            double f0 = f0Curve[a] + (f0Curve[a + 1] - f0Curve[a]) * (pos - a);
            jit += (Rnd() * 0.08 - jit) * 0.002;
            f0 *= 1 + jit + 0.02 * Math.Sin(ts * 2 * Math.PI * 5.5);
            ph += f0 / SR;
            if (ph >= 1) {
                ph -= 1; period++;
                sh = 1 + Rnd() * 0.35;
                // creak: every other pulse is weaker (period doubling) -> growl
                if (R.NextDouble() < creak && period % 2 == 0) sh *= 0.25;
            }
            // Rosenberg-like glottal pulse
            double g = ph < 0.4 ? 0.5 * (1 - Math.Cos(Math.PI * ph / 0.4)) : (ph < 0.6 ? Math.Cos(Math.PI * (ph - 0.4) / 0.4) : 0);
            double src = (g - 0.3) * sh;
            double breath = lpB.P(Rnd()) * noise * (0.6 + 0.4 * g);
            // formants move between vowels
            if (i % 64 == 0) {
                double vp = t * (vowels.Length - 1);
                int v = Math.Min((int)vp, vowels.Length - 2);
                double fr = vp - v;
                fr = fr * fr * (3 - 2 * fr);
                for (int k = 0; k < 4; k++) {
                    double ff = vowels[v][k] + (vowels[v + 1][k] - vowels[v][k]) * fr;
                    F[k].SetBP(ff, k == 0 ? 4.5 : 6.5, SR);
                }
            }
            double x = src + breath;
            double y = 0;
            for (int k = 0; k < 4; k++) y += F[k].P(x) * gains[k];
            // gurgle: random-rate amplitude flutter (liquid in the throat)
            gurT -= 1.0 / SR;
            if (gurT <= 0) { gurT = Rf(0.02, 0.06); gurA = Rf(0.3, 1.0); }
            gur += (gurA - gur) * 0.004;
            y *= 1 - gurgle + gurgle * gur;
            // envelope
            double env = Math.Min(1, ts / attack) * Math.Pow(1 - t, 0.6) * (0.75 + 0.25 * Math.Sin(t * Math.PI * 2.2 + 0.5));
            y *= env;
            // saturation
            y = Math.Tanh(y * grit) / Math.Tanh(grit);
            o[i] = lpO.P(hp.P(y));
        }
        return o;
    }

    // ------------------------------------------------------------------ footsteps by surface
    // kind: conc (asphalt/concrete), dirt, wood, metal, snow, sand, grass.
    // heel contact + toe contact, each = low thud + (hard surfaces) a bright click, plus surface
    // texture: grains (gravel, snow crunch, sand hiss), resonant modes (hollow boards, ringing sheet
    // metal) or a rustle (grass).
    static double[] StepS(string kind, int seed, double heavy) {
        R = new Random(seed);
        double thudF = 85, thudD = 0.016, thudA = 1.0, click = 0, clickF = 3000;
        double gDens = 0, gF1 = 2000, gF2 = 4500, gDec = 0.05, gA = 0.5, rustle = 0, scuff = 0.15, len = 0.32;
        double[][] modes = new double[0][];
        if (kind == "conc") { thudF = 105; thudD = 0.011; thudA = 0.8; click = 0.9; clickF = 3400; gDens = 0.004; gF1 = 3200; gF2 = 6500; gDec = 0.02; gA = 0.35; scuff = 0.3; }
        else if (kind == "wood") { thudF = 95; thudD = 0.018; thudA = 0.7; click = 0.35; clickF = 2200; scuff = 0.12;
            modes = new double[][] { new double[] { Rf(165, 190), 0.07, 1.0 }, new double[] { Rf(290, 320), 0.05, 0.6 }, new double[] { Rf(480, 540), 0.035, 0.35 }, new double[] { Rf(820, 900), 0.02, 0.2 } }; len = 0.36; }
        else if (kind == "metal") { thudF = 120; thudD = 0.01; thudA = 0.6; click = 0.8; clickF = 4200; scuff = 0.1;
            modes = new double[][] { new double[] { Rf(380, 430), 0.22, 0.55 }, new double[] { Rf(1050, 1150), 0.16, 0.4 }, new double[] { Rf(2150, 2350), 0.11, 0.3 }, new double[] { Rf(3400, 3600), 0.07, 0.18 } }; len = 0.6; }
        else if (kind == "snow") { thudF = 60; thudD = 0.03; thudA = 0.7; gDens = 0.09; gF1 = Rf(1000, 1400); gF2 = Rf(2600, 3200); gDec = 0.11; gA = 0.8; scuff = 0; len = 0.36; }
        else if (kind == "sand") { thudF = 65; thudD = 0.025; thudA = 0.6; gDens = 0.12; gF1 = 4200; gF2 = 7500; gDec = 0.07; gA = 0.35; scuff = 0.45; len = 0.34; }
        else if (kind == "grass") { thudF = 70; thudD = 0.022; thudA = 0.75; gDens = 0.006; gF1 = 1800; gF2 = 3600; gDec = 0.04; gA = 0.4; rustle = 0.5; scuff = 0.05; }
        else { return Step(seed, heavy); }
        int n = (int)(SR * (len + heavy * 0.12));
        var o = new double[n];
        var lpT = Biquad.LowPass(240 + heavy * 50, 0.7, SR);
        var hpC = Biquad.HighPass(clickF, 0.8, SR);
        var bp1 = Biquad.BandPass(gF1, 1.0, SR);
        var bp2 = Biquad.BandPass(gF2, 1.3, SR);
        var hpR = Biquad.HighPass(2600, 0.7, SR);
        var bpS = Biquad.BandPass(Rf(1500, 2500), 0.8, SR);
        var hp = Biquad.HighPass(45, 0.7, SR);
        double toe = Rf(0.05, 0.08) + heavy * 0.02;
        double f0 = thudF * Rf(0.9, 1.1) - heavy * 12;
        double ph = 0, grains = 0;
        var mph = new double[modes.Length];
        for (int i = 0; i < n; i++) {
            double t = (double)i / SR;
            double tt = t - toe;
            // contacts: heel (full) and toe (lighter)
            double eH = Math.Exp(-t / (thudD + heavy * 0.02)) * (1 - Math.Exp(-t / 0.0012));
            double eT = tt > 0 ? Math.Exp(-tt / (thudD * 0.8)) * (1 - Math.Exp(-tt / 0.0015)) * 0.55 : 0;
            ph += 2 * Math.PI * f0 * (1 + 0.5 * Math.Exp(-t / 0.008)) / SR;
            double thud = (Math.Sin(ph) * 0.8 + lpT.P(Rnd()) * 2.0) * (eH + eT) * thudA * (1 + heavy * 0.7);
            // click: a few ms of bright noise at each contact (hard sole on a hard floor)
            double cE = Math.Exp(-t / 0.0025) + (tt > 0 ? Math.Exp(-tt / 0.002) * 0.6 : 0);
            double cl = hpC.P(Rnd()) * cE * click;
            // resonant modes, excited by both contacts
            double res = 0;
            for (int k = 0; k < modes.Length; k++) {
                mph[k] += 2 * Math.PI * modes[k][0] / SR;
                double ek = Math.Exp(-t / modes[k][1]) + (tt > 0 ? 0.5 * Math.Exp(-tt / modes[k][1]) : 0);
                res += Math.Sin(mph[k]) * ek * modes[k][2] * (1 - Math.Exp(-t / 0.002));
            }
            // grains: crunch / grit / hiss, dense right after the contacts
            double dens = gDens * (Math.Exp(-t / gDec) + (tt > 0 ? 0.8 * Math.Exp(-tt / gDec) : 0)) + gDens * 0.03;
            if (R.NextDouble() < dens) grains += Rf(0.3, 1.0) * (R.NextDouble() < 0.5 ? -1 : 1);
            grains *= 0.82;
            double gr = (bp1.P(grains + Rnd() * 0.04) * 1.4 + bp2.P(grains) * 0.7) * gA;
            // grass rustle: soft high noise swell over the roll
            double ru = rustle > 0 ? hpR.P(Rnd()) * rustle * 0.25 * Math.Exp(-Math.Pow((t - 0.07) / 0.06, 2)) : 0;
            // scuff at the end of the roll
            double ts = t - toe - 0.015;
            double sc = ts > 0 ? bpS.P(Rnd()) * scuff * 0.3 * Math.Exp(-ts / 0.05) * (1 - Math.Exp(-ts / 0.01)) : 0;
            o[i] = hp.P(thud + cl * 0.5 + res * 0.35 + gr + ru + sc);
        }
        return o;
    }

    // ------------------------------------------------------------------ zombie extras
    // raspy breathing: noise through a slowly moving vowel, inhale + exhale with a wet rattle
    static double[] Breath(int seed, double dur) {
        R = new Random(seed);
        int n = (int)(SR * dur);
        var o = new double[n];
        var f1 = Biquad.BandPass(600, 3, SR);
        var f2 = Biquad.BandPass(1300, 4, SR);
        var f3 = Biquad.BandPass(2600, 5, SR);
        var hp = Biquad.HighPass(120, 0.7, SR);
        double rat = 0, ratT = 0;
        double split = Rf(0.38, 0.5);
        for (int i = 0; i < n; i++) {
            double t = (double)i / n;
            double ts = (double)i / SR;
            // inhale (quieter, higher), short gap, exhale (louder, lower)
            double env, sh;
            if (t < split) { double u = t / split; env = Math.Sin(Math.PI * u) * 0.55; sh = 1.25; }
            else if (t < split + 0.06) { env = 0; sh = 1; }
            else { double u = (t - split - 0.06) / (1 - split - 0.06); env = Math.Pow(Math.Sin(Math.PI * Math.Min(1, u)), 0.7); sh = 0.85; }
            if (i % 64 == 0) { f1.SetBP(600 * sh, 3, SR); f2.SetBP(1300 * sh, 4, SR); f3.SetBP(2600 * sh, 5, SR); }
            // rattle: phlegm flutter (random clicks ~30-60 Hz)
            ratT -= 1.0 / SR;
            if (ratT <= 0) { ratT = Rf(0.012, 0.035); rat = Rf(0.4, 1.0); }
            rat *= 0.995;
            double x = Rnd();
            double y = f1.P(x) * 1.0 + f2.P(x) * 0.7 + f3.P(x) * 0.35;
            y *= env * (0.55 + 0.45 * rat);
            o[i] = hp.P(Math.Tanh(y * 3) );
        }
        return o;
    }

    // foot dragged over the ground: long filtered scrape with a stuttering grip
    static double[] Drag(int seed) {
        R = new Random(seed);
        int n = (int)(SR * Rf(0.45, 0.65));
        var o = new double[n];
        var bp = Biquad.BandPass(Rf(900, 1400), 0.9, SR);
        var bp2 = Biquad.BandPass(Rf(2800, 3600), 1.4, SR);
        var lp = Biquad.LowPass(200, 0.7, SR);
        double st = 1, stT = 0, ph = 0;
        for (int i = 0; i < n; i++) {
            double t = (double)i / n;
            double ts = (double)i / SR;
            stT -= 1.0 / SR;
            if (stT <= 0) { stT = Rf(0.01, 0.04); st = Rf(0.3, 1.0); }
            double env = Math.Min(1, ts / 0.04) * Math.Pow(1 - t, 0.8);
            double x = Rnd();
            double y = (bp.P(x) * 1.2 + bp2.P(x) * 0.5) * st * env;
            // the shoe touching down at the start
            ph += 2 * Math.PI * 80 / SR;
            y += (Math.Sin(ph) * 0.6 + lp.P(Rnd()) * 1.5) * Math.Exp(-ts / 0.02) * (1 - Math.Exp(-ts / 0.002));
            o[i] = y;
        }
        return o;
    }

    // vowel formants F1..F4 (scaled down a bit for a bigger, deeper throat)
    static readonly double[] UH = { 520, 1000, 2300, 3300 };
    static readonly double[] AH = { 680, 1100, 2350, 3300 };
    static readonly double[] OH = { 450, 800, 2300, 3200 };
    static readonly double[] OO = { 330, 700, 2250, 3200 };
    static readonly double[] AE = { 620, 1550, 2400, 3300 };
    static readonly double[] RR = { 420, 1100, 1550, 3000 };

    public static void Run(string dir) {
        // footsteps: 6 variants + a heavier landing
        for (int i = 0; i < 6; i++) Save(Path.Combine(dir, "step" + (i + 1) + ".wav"), Step(100 + i * 17, 0), 0.55);
        Save(Path.Combine(dir, "land.wav"), Step(999, 1), 0.7);
        // groans: slow, low, moving vowels
        Save(Path.Combine(dir, "zgroan1.wav"), Voice(11, 1.9, new double[] { 78, 88, 82, 70, 62 }, new double[][] { OO, UH, AH, UH }, 0.6, 0.35, 2.5, 0.35, 0.25), 0.8);
        Save(Path.Combine(dir, "zgroan2.wav"), Voice(12, 1.5, new double[] { 95, 105, 90, 75 }, new double[][] { UH, AH, OH }, 0.7, 0.4, 3.0, 0.45, 0.15), 0.8);
        Save(Path.Combine(dir, "zgroan3.wav"), Voice(13, 2.3, new double[] { 70, 72, 80, 74, 66, 58 }, new double[][] { RR, OH, OO, UH, OH }, 0.8, 0.3, 3.5, 0.5, 0.35), 0.8);
        Save(Path.Combine(dir, "zgroan4.wav"), Voice(14, 1.2, new double[] { 110, 120, 98, 85 }, new double[][] { AE, AH, UH }, 0.5, 0.45, 2.8, 0.3, 0.08), 0.8);
        Save(Path.Combine(dir, "zgroan5.wav"), Voice(15, 1.7, new double[] { 64, 68, 74, 66, 60 }, new double[][] { OO, OO, UH, RR }, 0.9, 0.5, 4.0, 0.6, 0.3), 0.8);
        // attacks: short, higher, harsh snarl
        Save(Path.Combine(dir, "zattack1.wav"), Voice(21, 0.65, new double[] { 140, 190, 175, 120 }, new double[][] { RR, AE, AH }, 0.6, 0.8, 6.0, 0.25, 0.03), 0.9);
        Save(Path.Combine(dir, "zattack2.wav"), Voice(22, 0.55, new double[] { 160, 210, 150 }, new double[][] { AH, AE, RR }, 0.7, 0.9, 7.0, 0.3, 0.02), 0.9);
        // deaths: falling pitch, choking, long fade
        Save(Path.Combine(dir, "zdie1.wav"), Voice(31, 1.4, new double[] { 130, 115, 90, 65, 48 }, new double[][] { AH, AH, UH, OO }, 0.8, 0.6, 4.0, 0.7, 0.02), 0.85);
        Save(Path.Combine(dir, "zdie2.wav"), Voice(32, 1.1, new double[] { 150, 120, 80, 55 }, new double[][] { AE, AH, RR, OO }, 0.9, 0.7, 5.0, 0.8, 0.02), 0.85);
        // more voices: wetter, more broken groans, extra snarls and a choking death
        Save(Path.Combine(dir, "zgroan6.wav"), Voice(16, 2.6, new double[] { 66, 74, 92, 80, 70, 64, 58 }, new double[][] { OH, UH, AH, AH, UH, OO }, 0.85, 0.45, 3.8, 0.75, 0.4), 0.8);
        Save(Path.Combine(dir, "zgroan7.wav"), Voice(17, 1.4, new double[] { 88, 120, 104, 84 }, new double[][] { RR, AE, UH, OO }, 0.7, 0.55, 4.5, 0.55, 0.12), 0.8);
        Save(Path.Combine(dir, "zgroan8.wav"), Voice(18, 2.0, new double[] { 58, 62, 60, 66, 56, 50 }, new double[][] { OO, UH, OO, RR, OO }, 0.95, 0.6, 5.0, 0.85, 0.5), 0.8);
        Save(Path.Combine(dir, "zattack3.wav"), Voice(23, 0.75, new double[] { 120, 200, 230, 170, 110 }, new double[][] { UH, AE, AH, RR }, 0.65, 0.85, 7.5, 0.35, 0.02), 0.9);
        Save(Path.Combine(dir, "zattack4.wav"), Voice(24, 0.5, new double[] { 180, 240, 160 }, new double[][] { AE, AH, UH }, 0.5, 1.0, 8.0, 0.2, 0.015), 0.9);
        Save(Path.Combine(dir, "zdie3.wav"), Voice(33, 1.8, new double[] { 110, 125, 95, 70, 52, 44 }, new double[][] { AH, AE, UH, RR, OO }, 0.95, 0.75, 5.5, 0.9, 0.03), 0.85);
        // sprinters: a torn, high shriek when they start running
        Save(Path.Combine(dir, "zscream1.wav"), Voice(41, 1.1, new double[] { 260, 380, 420, 360, 240 }, new double[][] { AE, AE, AH, AH }, 0.4, 1.1, 9.0, 0.2, 0.04), 0.95);
        Save(Path.Combine(dir, "zscream2.wav"), Voice(42, 0.9, new double[] { 300, 440, 390, 280 }, new double[][] { AH, AE, AE }, 0.5, 1.2, 10.0, 0.25, 0.03), 0.95);
        // close-up breathing and dragged feet
        for (int i = 0; i < 3; i++) Save(Path.Combine(dir, "zbreath" + (i + 1) + ".wav"), Breath(51 + i, Rf(1.3, 1.9)), 0.7);
        for (int i = 0; i < 3; i++) Save(Path.Combine(dir, "zdrag" + (i + 1) + ".wav"), Drag(61 + i), 0.6);
        // footsteps for every surface: 4 variants + a landing each (st_<kind>N, ld_<kind>)
        string[] kinds = { "conc", "dirt", "wood", "metal", "snow", "sand", "grass" };
        for (int k = 0; k < kinds.Length; k++) {
            for (int i = 0; i < 4; i++) Save(Path.Combine(dir, "st_" + kinds[k] + (i + 1) + ".wav"), StepS(kinds[k], 200 + k * 31 + i * 7, 0), 0.55);
            Save(Path.Combine(dir, "ld_" + kinds[k] + ".wav"), StepS(kinds[k], 900 + k, 1), 0.7);
        }
    }
}
