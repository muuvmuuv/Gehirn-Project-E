module plug

import math

struct UpdateCase {
	name  string
	pilot []f64
	own   []f64
	ratio f64
	rate  f64 = 0.02
	want  f64
}

fn test_update() {
	cases := [
		UpdateCase{
			name:  'idle pilot is skipped'
			pilot: [0.0, 0.0]
			own:   [1.0, 0.0]
			ratio: 0.5
			want:  0.5
		},
		UpdateCase{
			name:  'pilot just under the idle line is skipped'
			pilot: [0.049, 0.0]
			own:   [1.0, 0.0]
			ratio: 0.5
			want:  0.5
		},
		UpdateCase{
			name:  'pilot at the idle line counts'
			pilot: [0.05, 0.0]
			own:   [1.0, 0.0]
			ratio: 0.5
			want:  0.491
		},
		UpdateCase{
			name:  'idle core is skipped'
			pilot: [1.0, 0.0]
			own:   [0.04, 0.0]
			ratio: 0.5
			want:  0.5
		},
		UpdateCase{
			name:  'core at the idle line counts'
			pilot: [1.0, 0.0]
			own:   [0.05, 0.0]
			ratio: 0.5
			want:  0.491
		},
		UpdateCase{
			name:  'agreement moves up at the rate'
			pilot: [1.0, 0.0]
			own:   [1.0, 0.0]
			ratio: 0.5
			want:  0.51
		},
		UpdateCase{
			name:  'a faster rate moves further'
			pilot: [1.0, 0.0]
			own:   [1.0, 0.0]
			ratio: 0.5
			rate:  0.5
			want:  0.75
		},
		UpdateCase{
			name:  'opposite directions move down'
			pilot: [1.0, 0.0]
			own:   [-1.0, 0.0]
			ratio: 0.5
			want:  0.49
		},
		UpdateCase{
			name:  'a right angle scores half'
			pilot: [0.0, 1.0]
			own:   [1.0, 0.0]
			ratio: 0.3
			want:  0.304
		},
		UpdateCase{
			name:  'half the core speed scores half'
			pilot: [0.5, 0.0]
			own:   [1.0, 0.0]
			ratio: 0.9
			want:  0.892
		},
		UpdateCase{
			name:  'twice the core speed scores half'
			pilot: [1.0, 0.0]
			own:   [0.5, 0.0]
			ratio: 0.9
			want:  0.892
		},
		UpdateCase{
			name:  'direction and magnitude multiply'
			pilot: [0.0, 0.5]
			own:   [1.0, 0.0]
			ratio: 0.0
			rate:  1.0
			want:  0.25
		},
	]
	for c in cases {
		mut s := Sync{
			ratio: c.ratio
			rate:  c.rate
		}
		s.update(c.pilot, c.own)
		assert math.abs(s.ratio - c.want) < 1e-12, '${c.name}: ${s.ratio}'
	}
}

fn test_authority() {
	// ratio, threshold, ceiling, authority
	cases := [
		[0.2, 0.3, 0.8, 0.0],
		[0.3, 0.3, 0.8, 0.0],
		[0.65, 0.3, 0.8, 0.4],
		[1.0, 0.3, 0.8, 0.8],
		[1.5, 0.3, 0.8, 0.8],
		[0.5, 0.0, 1.0, 0.5],
		[1.0, 1.0, 0.8, 0.0], // 1 - threshold is 0, so only <= keeps this finite
	]
	for c in cases {
		s := Sync{
			ratio: c[0]
		}
		got := s.authority(c[1], c[2])
		assert math.abs(got - c[3]) < 1e-12, '${c}: ${got}'
	}
}
