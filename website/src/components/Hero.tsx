import { Link } from '@tanstack/react-router'
import { motion } from 'motion/react'
import { STEP, useReveal } from '../lib/reveal'
import { REPO } from '../lib/site'
import { Clip } from './Clip'
import { Frame } from './Frame'
import { Term } from './Term'

/** The landing page's opening: the README's first sentence, `just demo`, and MAGI refusing a drop on hosted models. */
export function Hero() {
	return (
		<section className="hero" aria-labelledby="h-hero">
			<div className="hero__copy">
				<motion.div className="eyebrow" {...useReveal()}>
					<span>Project E</span>
					<span className="jp">E計画</span>
					<span>A fan project</span>
				</motion.div>
				<motion.h1 className="h1 hero__title" id="h-hero" {...useReveal(STEP)}>
					Evangelion's <em>MAGI</em> as a robot's safety gate
				</motion.h1>
				<motion.p className="lede" {...useReveal(2 * STEP)}>
					Three model families vote on every goal. Anything irreversible needs all three. A
					restraint armor with no model in it holds the body.
				</motion.p>
				<motion.div className="hero__cta" {...useReveal(3 * STEP)}>
					<Term command="just demo" />
					<p className="hero__note">No API keys: scripted models and a simulated body.</p>
					<div className="hero__links">
						<a href={REPO}>Read the code ↗</a>
						<Link to="/bridge">Reading the bridge →</Link>
					</div>
				</motion.div>
			</div>
			<motion.figure className="hero__media" {...useReveal(2 * STEP)}>
				<Frame label="MAGI" jp="決議" aside="Release · needs 3 of 3">
					<div className="shot shot--scan">
						<Clip
							src="/media/magi.mp4"
							poster="/media/magi.png"
							width={800}
							height={448}
							eager
							label="The MAGI panel of gehirn's bridge. A payload release is up for a vote: BALTHASAR-2 on Jev and MELCHIOR-1 on gpt-oss-20b vote 否決, rejected, CASPER-3 on llama-3.1-8b votes 可決, approved, so it fails 1 of 3. At the next vote all three approve, 3 of 3."
						/>
					</div>
				</Frame>
				<figcaption className="cap">
					<span className="tag tag--real">Real</span>the votes of three hosted models, gpt-oss-20b,
					Jev and llama-3.1-8b: the drop fails 1 of 3 with a person 1.04 m away and passes 3 of 3 at
					3.88 m. <span className="tag tag--staged">Scripted</span>the core that asks for the drop.
					Recorded on 2026-10-05.
				</figcaption>
			</motion.figure>
		</section>
	)
}
