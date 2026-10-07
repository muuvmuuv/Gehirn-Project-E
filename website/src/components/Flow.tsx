import { motion, useReducedMotion } from 'motion/react'
import { EASE_OUT } from '../lib/reveal'

/** The stages a goal passes, HQ's two first and the field unit's three after the umbilical. */
const STAGES = [
	{ jp: '提訴', name: 'Core', text: 'A language model proposes the next goal, with its reason.' },
	{ jp: '決議', name: 'MAGI', text: 'Three judges from three model families vote on it.' },
	{ jp: 'シンクロ率', name: 'Seat', text: 'A pilot steers, or the dummy plug cloned from one.' },
	{ jp: '拘束具', name: 'Armor', text: 'Plain code restrains every command, 50 times a second.' },
	{
		jp: '本体',
		name: 'Body',
		text: 'Simulated today, planar or with MuJoCo physics. Hardware replaces it below the armor.',
	},
]

/**
 * How a goal travels from the core to the body, laid out as HQ and the field unit with the
 * umbilical between them. The wires between the stages draw in once, in the goal's direction.
 */
export function Flow() {
	const reduce = useReducedMotion()

	return (
		<section className="section" id="how" aria-labelledby="h-how">
			<div className="head">
				<h2 className="h2" id="h-how">
					How a goal travels
				</h2>
				<p>HQ thinks about once a second. The field loop runs at 50 Hz and never waits for it.</p>
			</div>
			<div className="flow">
				<div className="flow__lanes" aria-hidden="true">
					<div className="flow__lane flow__lane--hq">
						HQ <b>about 1 Hz</b>
					</div>
					<div className="flow__lane flow__lane--field">
						Field unit <b>50 Hz</b>
					</div>
				</div>
				<ol className="flow__stages">
					{STAGES.map((s, i) => (
						<li key={s.name} className="stage">
							<span className="stage__jp jp">{s.jp}</span>
							<h3>{s.name}</h3>
							<p>{s.text}</p>
							{i < STAGES.length - 1 && (
								<motion.span
									className={i === 1 ? 'wire wire--umbilical' : 'wire'}
									aria-hidden="true"
									initial={reduce ? false : { transform: 'scale(0, 1)' }}
									whileInView={{ transform: 'scale(1, 1)' }}
									viewport={{ once: true, amount: 0.6 }}
									transition={{ duration: 0.35, ease: EASE_OUT, delay: 0.2 + i * 0.25 }}
								/>
							)}
						</li>
					))}
				</ol>
				<p className="flow__umbilical">
					<span>
						Umbilical cable <span className="jp">アンビリカルケーブル</span> signed, over Zenoh
					</span>
				</p>
			</div>
		</section>
	)
}
