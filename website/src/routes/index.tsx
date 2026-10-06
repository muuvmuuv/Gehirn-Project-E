import { createFileRoute } from '@tanstack/react-router'
import { BridgeTeaser } from '../components/BridgeTeaser'
import { Flow } from '../components/Flow'
import { Footer } from '../components/Footer'
import { Hero } from '../components/Hero'
import { Measured } from '../components/Measured'
import { Nav } from '../components/Nav'
import { Parts } from '../components/Parts'
import { Rules } from '../components/Rules'
import { RunIt } from '../components/RunIt'
import { Scenes } from '../components/Scenes'

/** The landing page: the pitch, the rules, how a goal travels, the scenes, the parts, the bridge, the numbers and `just demo`. */
export const Route = createFileRoute('/')({
	head: () => ({ meta: [{ title: "gehirn · Evangelion's MAGI as a robot's safety gate" }] }),
	component: Landing,
})

function Landing() {
	return (
		<div className="page">
			<a className="skip" href="#main">
				Skip to content
			</a>
			<div className="hazard" aria-hidden="true" />
			<div className="wrap">
				<Nav />
				<main id="main">
					<Hero />
					<Rules />
					<Flow />
					<Scenes />
					<Parts />
					<BridgeTeaser />
					<Measured />
					<RunIt />
				</main>
				<Footer />
			</div>
		</div>
	)
}
