import { motion, useReducedMotion } from 'motion/react'
import { STEP, reveal } from '../lib/reveal'
import { Frame } from './Frame'

/** Three tools that test and move the body, each with the switch or command that turns it on. */
const TOOLS = [
	{
		label: 'World generator',
		jp: '世界生成',
		title: 'A model that hunts for failures',
		text: 'A hosted model writes worlds, gehirn flies them, and every failure goes back into the next prompt. A world counts only once a reference solves it. A hunt costs a few cents.',
		fact: 'It found a goto onto a person that MAGI approved, now a scenario in the gate, and traps where the plain reflex stalls for good.',
		run: 'tools/worldgen.py',
	},
	{
		label: 'Local planner',
		jp: '経路計画',
		title: "Steers around people's paths",
		text: "It plans the way around solids and each walker's predicted course, 32 headings a tick, with no model in it. The armor still checks every command.",
		fact: 'It keeps people at least 0.69 m away where the bare reflex let a walker come to 0.27 m, and it delivered on every trap world where the reflex stalled.',
		run: 'PLANNER=local',
	},
	{
		label: 'Physics body',
		jp: '物理',
		title: 'A base with mass',
		text: 'On MuJoCo the body brakes over its own distance, so the armor widens every keep by it. The field unit builds as one static binary for Linux on musl.',
		fact: 'The same mission, the same armor and the same MAGI fly the planar body and the physics base alike.',
		run: 'just body=mujoco demo',
	},
]

/** The landing page's tools: the world generator, the local planner and the MuJoCo body. */
export function Lab() {
	const reduce = useReducedMotion()

	return (
		<section className="section" id="lab" aria-labelledby="h-lab">
			<div className="head">
				<h2 className="h2" id="h-lab">
					Built to be broken <span className="jp">試験</span>
				</h2>
				<p>
					gehirn tries to break itself, steers smarter on request and drives a body with real
					physics.
				</p>
			</div>
			<div className="lab">
				{TOOLS.map((t, i) => (
					<motion.div key={t.label} {...reveal(i * STEP, reduce)}>
						<Frame label={t.label} jp={t.jp} className="lab-card">
							<div className="lab-card__body">
								<h3>{t.title}</h3>
								<p>{t.text}</p>
								<p className="lab-card__fact">{t.fact}</p>
								<code className="lab-card__run">{t.run}</code>
							</div>
						</Frame>
					</motion.div>
				))}
			</div>
		</section>
	)
}
