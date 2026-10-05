# Safety

The armor owns the body, and `main` never gets a handle to it. Every command passes a speed cap (1.0 m/s manned, 0.4 unmanned), an acceleration limit that never limits braking, a geofence, and speed and separation monitoring: slower from 2 m to a human, and inside 0.7 m nothing moves toward them. Nothing pushes into anything solid either; what remains of a command slides along the surface. Irreversible effectors need all three MAGI and no human within 2 m.

That is a soft layer on operating systems without real time guarantees. On hardware the same limits run again on the motor controller behind a physical e-stop, and the controller zeroes its outputs when commands go stale, as the simulator does after 200 ms. The reasoning is in [ADR 0001](adr/0001-where-it-runs.md).
