import { createFileRoute } from '@tanstack/react-router'
import { BridgeTeaser } from '../components/BridgeTeaser'
import { Flow } from '../components/Flow'
import { Hero } from '../components/Hero'
import { Lab } from '../components/Lab'
import { Measured } from '../components/Measured'
import { Parts } from '../components/Parts'
import { Rules } from '../components/Rules'
import { RunIt } from '../components/RunIt'
import { Scenes } from '../components/Scenes'
import { Terrain } from '../components/Terrain'

/**
 * The landing page: the pitch, the rules, how a goal travels, the worlds, the scenes, the tools
 * that test the stack, the parts, the bridge, the numbers and `just demo`.
 */
export const Route = createFileRoute('/')({
	head: () => ({ meta: [{ title: "gehirn · Evangelion's MAGI as a robot's safety gate" }] }),
	component: Landing,
})

function Landing() {
	return (
		<>
			<Hero />
			<Rules />
			<Flow />
			<Terrain />
			<Scenes />
			<Lab />
			<Parts />
			<BridgeTeaser />
			<Measured />
			<RunIt />
		</>
	)
}
