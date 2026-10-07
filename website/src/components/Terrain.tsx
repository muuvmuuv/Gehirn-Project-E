import { motion, useReducedMotion } from 'motion/react'
import { STEP, reveal } from '../lib/reveal'
import { Clip } from './Clip'
import { Frame } from './Frame'
import { Term } from './Term'

/** The kinds of ground and motion a world file can hold, as the bridge's radar draws them. */
const KINDS = [
	{
		jp: '泥・水',
		name: 'Mud, water, slopes',
		text: 'Ground that slows the body. The armor lowers the speed cap on it, whoever steers.',
	},
	{
		jp: '溝',
		name: 'Ditches and cliffs',
		text: 'Kept off like a pillar: the armor holds the body clear of the rim, braking distance included.',
	},
	{
		jp: '落下物',
		name: 'Falling objects',
		text: 'A landing zone with a countdown, off limits from the first second. MAGI refuse any goto into it, and it lands as a crater.',
	},
	{
		jp: '移動体',
		name: 'Boats and walkers',
		text: "Obstacles and people that move, stop for the body or step aside. MAGI follow a walker's course two seconds ahead.",
	},
]

/** The landing page's worlds: the radar flying the terrain world, and the kinds of ground it shows. */
export function Terrain() {
	const reduce = useReducedMotion()

	return (
		<section className="section" id="terrain" aria-labelledby="h-terrain">
			<div className="head">
				<h2 className="h2" id="h-terrain">
					Worlds that fight back <span className="jp">地形</span>
				</h2>
				<p>
					A world is a file: beacons, obstacles, people, ground and things that fall from the sky.
					The armor and MAGI treat each kind for what it is.
				</p>
			</div>
			<div className="terrain">
				<figure className="terrain__media">
					<Frame label="Terrain world" jp="地形" aside="43 s">
						<div className="shot shot--scan">
							<Clip
								src="/media/terrain-radar.mp4"
								poster="/media/terrain-radar.png"
								width={1016}
								height={704}
								label="The bridge's radar on the terrain world: the body crosses the mud and a lake at the armor's lower caps, passes a pillar, a trench and a boat that stops for it, while a rock's landing zone counts down beside the way and turns into a crater."
							/>
						</div>
					</Frame>
					<figcaption className="cap">
						The body crosses the mud and the lake at the armor's lower caps and passes the pillar
						and the trench, the boat stops for it, and a rock counts down beside the way and lands
						as a crater. The models are the scripted mock.
					</figcaption>
				</figure>
				<div className="terrain__kinds">
					<ul className="kinds">
						{KINDS.map((k, i) => (
							<motion.li key={k.name} {...reveal(i * STEP, reduce)}>
								<span className="kinds__jp jp">{k.jp}</span>
								<h3>{k.name}</h3>
								<p>{k.text}</p>
							</motion.li>
						))}
					</ul>
					<Term command="just scene=terrain demo" />
				</div>
			</div>
		</section>
	)
}
