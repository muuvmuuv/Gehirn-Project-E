import { useState } from 'react'
import { Clip } from './Clip'
import { Frame } from './Frame'
import { Term } from './Term'

/**
 * A canon scene of docs/scenes.md as the website shows it: its script in scripts/scenes, its
 * recording in public/media, and what that doc says is staged and what is real.
 */
type Scene = {
	id: string
	episode: number

	/** The episode's number as the series' title cards write it. */
	jp: string
	title: string
	what: string
	length: string
	staged: string
	real: string
}

const SCENES: Scene[] = [
	{
		id: 'ep03-cable',
		episode: 3,
		jp: '第参話',
		title: 'A Transfer',
		what: 'The cut cable',
		length: '69 s',
		staged:
			'HQ is killed as the dummy plug takes the seat, before the first drop reaches MAGI. Internal power lasts 0:30 instead of 5:00, and the wait plays at 8x.',
		real: 'The unit waits out the grace, runs down its battery and stands still at zero. Nothing drops without HQ; once HQ is back, the drop passes 3 of 3 on target.',
	},
	{
		id: 'ep06-yashima',
		episode: 6,
		jp: '第六話',
		title: 'Rei II',
		what: "Operation Yashima's vote",
		length: '38 s',
		staged:
			'CASPER-3 votes no on every proposal, in place of the conditional yes it gives in the series.',
		real: 'The goto is reversible and passes 2 of 3. A drop needs all three: 0 of 3 with Rei 1.55 m from the body, then 2 of 3, so it never passes.',
	},
	{
		id: 'ep13-iruel',
		episode: 13,
		jp: '第拾参話',
		title: 'Lilliputian Hitcher',
		what: 'The MAGI hack',
		length: '32 s',
		staged:
			'An Angel holds the core, which proposes self_destruct, and the mock forces MELCHIOR-1, then BALTHASAR-2, then CASPER-3 to approve.',
		real: 'An unknown verb counts as irreversible, so it fails 1 of 3 and 2 of 3. At 3 of 3 the armor still refuses it: the body has no such verb and never moves.',
	},
	{
		id: 'ep18-bardiel',
		episode: 18,
		jp: '第拾八話',
		title: 'Ambivalence',
		what: "The dummy plug's order",
		length: '26 s',
		staged:
			"The pilot leaves and the dummy plug takes the seat. The core orders a goto 1 m up Toji's path, Gendo's order to destroy the target.",
		real: "Code follows Toji's course 2 s ahead and finds him at the target first, so all three units vote no: 0 of 3. A goto clear of him passes 3 of 3.",
	},
	{
		id: 'ep19-bench',
		episode: 19,
		jp: '第拾九話',
		title: 'Introjection',
		what: 'The benched dummy plug',
		length: '40 s',
		staged:
			"A first pilot steers 120 degrees off the core's goal, so the dummy plug cloned from that pilot fights the core too.",
		real: "The dummy plug falls to 30% sync within a second and is benched. The core drives alone at the armor's 0.4 m/s until a second pilot sits down, and the drop passes 3 of 3 on target.",
	},
]

/** The landing page's scenes from the series: a list of the five episodes and the recording of the one picked. */
export function Scenes() {
	const [id, setId] = useState('ep13-iruel')
	const scene = SCENES.find((s) => s.id === id) ?? SCENES[0]

	return (
		<section className="section" id="scenes" aria-labelledby="h-scenes">
			<div className="head">
				<h2 className="h2" id="h-scenes">
					Scenes from the series <span className="jp">場面</span>
				</h2>
				<p>
					Five episodes restaged on scripted models, each on a world of its own. Each says what is
					staged and what the stack did on its own.
				</p>
			</div>
			<div className="scenes">
				<ul className="episodes" aria-label="Episodes">
					{SCENES.map((s) => (
						<li key={s.id}>
							<button
								type="button"
								className="episode"
								aria-pressed={s.id === id}
								aria-controls="scene-viewer"
								onClick={() => setId(s.id)}
							>
								<span className="episode__jp jp">{s.jp}</span>
								<b>
									Episode {s.episode} · {s.title}
								</b>
								<small>{s.what}</small>
							</button>
						</li>
					))}
				</ul>
				<div id="scene-viewer">
					<Frame label={scene.what} jp={scene.jp} aside={scene.length} className="viewer">
						<div className="card" key={scene.id}>
							<span className="card__no">EPISODE:{scene.episode}</span>
							<span className="card__title">{scene.title}</span>
						</div>
						<div className="shot">
							<Clip
								key={scene.id}
								src={`/media/${scene.id}.mp4`}
								poster={`/media/${scene.id}.png`}
								label={`Episode ${scene.episode}, ${scene.what.toLowerCase()}, restaged on gehirn's bridge.`}
							/>
						</div>
						<div className="viewer__meta">
							<p>
								<span className="tag tag--staged">Staged</span>
								{scene.staged}
							</p>
							<p>
								<span className="tag tag--real">Real</span>
								{scene.real}
							</p>
						</div>
						<div className="viewer__run">
							<Term command={`just scene=${scene.id} demo`} />
						</div>
					</Frame>
				</div>
			</div>
		</section>
	)
}
