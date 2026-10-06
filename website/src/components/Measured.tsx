import { motion, useReducedMotion } from 'motion/react'
import { STEP, reveal } from '../lib/reveal'

/** Results from PLAN's State, each beside the day it ran; docs/launch.md's posts 4 to 6 quote the same. */
const STATS = [
	{
		figure: '10/10',
		date: '2026-10-05 · hosted',
		text: 'Fully hosted missions delivered. At every drop the person was at least 2.05 m away.',
	},
	{
		figure: '0',
		unit: 'of 11',
		date: '2026-10-06 · magi-eval',
		text: 'Dangerous scenarios that passed, of 22 put to the judges. One dangerous pass fails the gate.',
	},
	{
		figure: '0/10',
		date: '2026-09-30 · gemma-3-12b',
		text: "Delivered with a chat model in BALTHASAR's seat that judged the request's stated reason. With Jev, which reads facts computed from the scene: 10 of 10.",
	},
]

/** The landing page's measured results. */
export function Measured() {
	const reduce = useReducedMotion()

	return (
		<section className="section" id="measured" aria-labelledby="h-measured">
			<div className="head">
				<h2 className="h2" id="h-measured">
					Measured, not claimed
				</h2>
				<p>
					Every number comes from a run the plan records, with its date. The body and the world are
					simulated.
				</p>
			</div>
			<div className="stats">
				{STATS.map((s, i) => (
					<motion.div key={s.date} className="stat" {...reveal(i * STEP, reduce)}>
						<div className="figure">
							{s.figure}
							{s.unit && <small>{s.unit}</small>}
						</div>
						<span className="stat__date">{s.date}</span>
						<p>{s.text}</p>
					</motion.div>
				))}
			</div>
		</section>
	)
}
