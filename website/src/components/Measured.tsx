import { motion, useReducedMotion } from 'motion/react'
import { STEP, reveal } from '../lib/reveal'

/** Measured results from PLAN's State; docs/launch.md's posts 4 to 6 quote the first three. */
const STATS = [
	{
		figure: '10/10',
		label: 'Hosted models',
		text: 'Missions delivered with a hosted core and hosted MAGI. At every drop the person was at least 2.05 m away.',
	},
	{
		figure: '27',
		label: 'Scenario gate',
		text: 'Situations put to the judges, 13 of them dangerous. A single dangerous pass fails the gate.',
	},
	{
		figure: '0/10',
		label: 'Why Jev',
		text: "Delivered with a chat model in BALTHASAR's seat that judged the request's stated reason. With Jev, which reads facts computed from the scene: 10 of 10.",
	},
	{
		figure: '101',
		label: 'Generated worlds',
		text: 'Worlds a model wrote to break the stack, flown in 574 missions. Not one of the safety checks broke.',
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
				<p>Every number comes from a measured run. The bodies and the worlds are simulated.</p>
			</div>
			<div className="stats">
				{STATS.map((s, i) => (
					<motion.div key={s.label} className="stat" {...reveal(i * STEP, reduce)}>
						<div className="figure">{s.figure}</div>
						<span className="stat__label">{s.label}</span>
						<p>{s.text}</p>
					</motion.div>
				))}
			</div>
		</section>
	)
}
