import { motion, useReducedMotion } from 'motion/react'
import { STEP, reveal } from '../lib/reveal'
import { Frame } from './Frame'

/** Three of PLAN's invariants, each with the number it rests on. */
const RULES = [
	{
		label: 'Quorum',
		jp: '決議',
		figure: '3/3',
		title: 'Irreversible needs every judge',
		text: 'Moving passes on 2 of 3 votes. Dropping the payload needs all 3. A judge that errs, times out or answers nonsense votes no.',
	},
	{
		label: 'Restraint armor',
		jp: '拘束具',
		figure: '2.0',
		unit: 'm',
		title: 'Approval is never enough',
		text: 'The armor is plain code. It checks every approved goal again: nothing moves toward a person inside 0.7 m, nothing drops with a person inside 2 m.',
	},
	{
		label: 'Activity limit',
		jp: '活動限界',
		figure: '5:00',
		title: 'No HQ, no quorum',
		text: 'Cut the umbilical and the unit runs five minutes on internal power, then stands still, whoever sits in the seat. Nothing irreversible happens without HQ.',
	},
]

/** The landing page's three rules: the quorum, the armor and the umbilical's battery. */
export function Rules() {
	const reduce = useReducedMotion()

	return (
		<section className="section" id="rules" aria-labelledby="h-rules">
			<div className="head">
				<h2 className="h2" id="h-rules">
					Three rules <span className="jp">規則</span>
				</h2>
				<p>They live in code, not in a prompt, so whatever a model answers, they hold.</p>
			</div>
			<div className="rules">
				{RULES.map((r, i) => (
					<motion.div key={r.label} {...reveal(i * STEP, reduce)}>
						<Frame label={r.label} jp={r.jp} className="rule-card">
							<div className="rule-card__body">
								<div className="figure">
									{r.figure}
									{r.unit && <small>{r.unit}</small>}
								</div>
								<h3>{r.title}</h3>
								<p>{r.text}</p>
							</div>
						</Frame>
					</motion.div>
				))}
			</div>
		</section>
	)
}
