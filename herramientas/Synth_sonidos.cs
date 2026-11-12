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
    }
}
