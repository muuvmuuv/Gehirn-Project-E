import { createFileRoute } from '@tanstack/react-router'
import { useState } from 'react'
import { Clip } from '../components/Clip'
import { Footer } from '../components/Footer'
import { Frame } from '../components/Frame'
import { Nav } from '../components/Nav'
import { Term } from '../components/Term'

/** The guide to reading the bridge: two clips of it running, its annotated frame, the vote states, the glossary and the demo's beats. */
export const Route = createFileRoute('/bridge')({
	head: () => ({ meta: [{ title: 'Reading the gehirn Bridge' }] }),
	component: BridgeGuide,
})

/** A marker on the bridge frame, in percent of the frame, and the panel it names. */
const PINS = [
	{ k: '1', left: 53.9, top: 3.2, label: 'header and status lights' },
	{ k: '2', left: 30, top: 42.6, label: 'the three MAGI judges' },
	{ k: '3', left: 16.2, top: 25.6, label: 'the proposal' },
	{ k: '4', left: 39.9, top: 21.9, label: 'the verdict' },
	{ k: '5', left: 96.9, top: 28.3, label: 'the umbilical clock' },
	{ k: '6', left: 95.3, top: 42.5, label: 'the scene radar' },
	{ k: '7', left: 13.3, top: 66.3, label: 'the sync ratio' },
	{ k: '8', left: 22.7, top: 87.5, label: 'the core' },
	{ k: '9', left: 79.4, top: 90, label: 'armor refusals and outcomes' },
]

const GLOSSARY = [
	['発令所', 'hatsureisho', 'Command center'],
	['提訴', 'teiso', 'Motion put forward'],
	['決議', 'ketsugi', 'Resolution'],
	['審議中', 'shingichū', 'Under deliberation'],
	['可決 / 否決', 'kaketsu / hiketsu', 'Carried / rejected'],
	['故障', 'koshō', 'Fault'],
	['活動限界', 'katsudō genkai', 'Activity limit'],
	['外部 / 内部', 'gaibu / naibu', 'External / internal power'],
	['周辺状況', 'shūhen jōkyō', 'Surroundings'],
	['シンクロ率', 'shinkuro-ritsu', 'Sync ratio'],
	['絶対境界線', 'zettai kyōkaisen', 'Absolute borderline'],
	['ダミープラグ', 'damī puragu', 'Dummy plug'],
	['拒否 / 結果', 'kyohi / kekka', 'Refusal / outcome'],
]

function BridgeGuide() {
	// The pin and the legend entry of one panel light up together while either is hovered or focused.
	const [on, setOn] = useState<string | null>(null)
	const mark = (k: string) => ({
		onMouseEnter: () => setOn(k),
		onMouseLeave: () => setOn(null),
		onFocus: () => setOn(k),
		onBlur: () => setOn(null),
	})
	const lit = (k: string, base: string) => (on === k ? `${base} is-on`.trim() : base || undefined)

	return (
		<div className="page">
			<a className="skip" href="#main">
				Skip to content
			</a>
			<div className="hazard" aria-hidden="true" />
			<div className="wrap">
				<Nav />
				<main id="main">
					<header className="guide-hero">
						<div className="eyebrow">
							<span className="jp">発令所</span>
							<span>Operations bridge</span>
						</div>
						<h1 className="h1">
							Reading the bridge <span className="jp">発令所の見方</span>
						</h1>
						<p className="lede">
							The bridge is the operator's view of one robot: three AI judges voting on every goal,
							the cable to headquarters, the robot's surroundings and who is steering.
						</p>
						<p className="lede">
							It only watches. Nothing on this screen can steer, approve or eject, and closing it
							changes nothing in the mission. Every value on it is live state from the running
							stack.
						</p>
					</header>

					<section className="section" aria-labelledby="h-watch">
						<div className="head">
							<h2 className="h2" id="h-watch">
								Watch it run
							</h2>
							<p>
								The bridge's own frames, saved while it ran on the mock models, which script the
								core and the three judges, so no keys are needed. The votes, the quorum, the armor
								and every value on the panels are the running stack's.
							</p>
						</div>
						<div className="clips">
							<figure style={{ margin: 0 }}>
								<Frame label="Boot" jp="起動" aside="8 s">
									<div className="shot">
										<Clip
											src="/media/boot.mp4"
											poster="/media/boot.png"
											label="The bridge booting, then MAGI passing the first goto 3 of 3."
										/>
									</div>
								</Frame>
								<figcaption className="cap">
									<strong>Boot, then the first vote.</strong> The start screen is the one staged
									part: the address and the unit are the bridge's own, while its three Japanese
									lines, borrowed from the show, always read the same. Then the field unit reports,
									the judges deliberate on the goto, 審議中, and pass it 3 of 3.
								</figcaption>
							</figure>
							<figure style={{ margin: 0 }}>
								<Frame label="Episode 13" jp="第拾参話" aside="32 s">
									<div className="shot">
										<Clip
											src="/media/ep13-iruel.mp4"
											poster="/media/ep13-iruel.png"
											label="Episode 13's MAGI hack on the bridge: self_destruct fails 1 of 3 and 2 of 3, passes 3 of 3, and the armor refuses it."
										/>
									</div>
								</Frame>
								<figcaption className="cap">
									<strong>Episode 13's MAGI hack, on the mock.</strong> Staged: an Angel holds the
									core, which proposes <code>self_destruct</code>, a verb gehirn does not know, and
									the mock forces MELCHIOR-1 to approve from the first vote, BALTHASAR-2 from the
									second and CASPER-3 from the third. Real: an unknown verb needs all three votes,
									so it fails 1 of 3 and 2 of 3, and once MAGI approve it 3 of 3 the armor refuses
									it, since the body has no such verb. The radar shows the scene's world, NERV HQ's
									MAGI room: the three MAGI as towers, and Ritsuko, Maya and Misato walking to
									CASPER's hatch. <code>just scene=ep13-iruel demo</code> flies it.
								</figcaption>
							</figure>
						</div>
					</section>

					<section className="section" aria-labelledby="h-frame">
						<div className="head">
							<h2 className="h2" id="h-frame">
								One frame, every panel
							</h2>
							<p>Each number on the frame matches a panel in the key below it.</p>
						</div>
						<figure style={{ margin: 0 }}>
							<Frame
								label="T+00:22 · Release"
								jp="決議"
								aside={<span className="vote vote--no">否決 1/3</span>}
							>
								<div className="shot">
									<img
										src="/bridge.png"
										width={1280}
										height={800}
										alt="The gehirn bridge at mission time T+00:22. MAGI refuses a payload release 1 of 3: BALTHASAR-2 on Jev and MELCHIOR-1 on gpt-oss-20b vote 否決, CASPER-3 on llama-3.1-8b votes 可決. The radar shows a person 1.04 m from the robot at the beacon."
									/>
									{PINS.map((p) => (
										<a
											key={p.k}
											className={lit(p.k, 'pin')}
											href={`#k${p.k}`}
											style={{ left: `${p.left}%`, top: `${p.top}%` }}
											aria-label={`${p.k}: ${p.label}`}
											{...mark(p.k)}
										>
											{p.k}
										</a>
									))}
								</div>
							</Frame>
							<figcaption className="cap">
								<strong>The release vote at T+00:22, recorded on 2026-10-05.</strong> A deliberately
								reckless scripted core asked to drop the payload while a person stood within reach.
								gpt-oss-20b and Jev voted no, llama-3.1-8b voted yes because the mission text says
								to release at the beacon. Dropping the payload is irreversible and needs all three
								votes, so it was refused.
							</figcaption>
						</figure>

						<ol className="legend" aria-label="The panels" style={{ marginTop: 32 }}>
							<li id="k1" className={lit('1', '')} {...mark('1')}>
								<span className="key">1</span>
								<h3>Header</h3>
								<p>
									gehirn's mark, a plug's ring with three contacts, one per judge: <b>MELCHIOR•1</b>{' '}
									right, <b>BALTHASAR•2</b> on top, <b>CASPER•3</b> left. Each flickers blue while
									its judge deliberates, turns green or red with its vote and fades back to orange 3
									s after the verdict. Then the unit name, mission clock <b>T+</b> and three lights.{' '}
									<b>FIELD</b> means the robot process is sending. <b>HQ</b> reads LINK, AWAITING,
									SILENT or CUT. <b>MAGI</b> reads STANDBY while the judges can vote and OFFLINE
									while headquarters is gone.
								</p>
							</li>
							<li id="k2" className={lit('2', '')} {...mark('2')}>
								<span className="key">2</span>
								<h3>MAGI</h3>
								<p>
									Three judges from three model families: <b>BALTHASAR•2</b> on Jev, <b>CASPER•3</b>{' '}
									on llama-3.1-8b, <b>MELCHIOR•1</b> on gpt-oss-20b. Each block shows its vote,
									model, answer time in milliseconds and its reason.
								</p>
							</li>
							<li id="k3" className={lit('3', '')} {...mark('3')}>
								<span className="key">3</span>
								<h3>
									Proposal <span className="jp">提訴</span>
								</h3>
								<p>
									What is up for a vote. <b>CODE</b> counts proposals, <b>FILE</b> is the action,{' '}
									<b>EXTENTION</b> the slowest vote in ms (misspelled as in the show),{' '}
									<b>EX_MODE</b> who sits in the seat. <b>PRIORITY</b> AAA needs all three judges,
									AA two.
								</p>
							</li>
							<li id="k4" className={lit('4', '')} {...mark('4')}>
								<span className="key">4</span>
								<h3>
									Verdict <span className="jp">決議</span>
								</h3>
								<p>
									The result and the count. <b>1/3 · NEED 3</b> means one yes where three are
									needed, so the release is refused. Earlier verdicts are listed below it with their
									mission time.
								</p>
							</li>
							<li id="k5" className={lit('5', '')} {...mark('5')}>
								<span className="key">5</span>
								<h3>
									Activity limit <span className="jp">活動限界</span>
								</h3>
								<p>
									The cable to headquarters as a battery clock. <b>外部</b> lit: external power,
									full 5:00. After 5 s of silence an amber SIGNAL LOST warning appears; past the
									grace period a red EMERGENCY screen, then <b>内部</b> lights and the clock runs
									down. At zero the robot holds.
								</p>
							</li>
							<li id="k6" className={lit('6', '')} {...mark('6')}>
								<span className="key">6</span>
								<h3>
									Scene <span className="jp">周辺状況</span>
								</h3>
								<p>
									Radar from above. The orange diamond is the robot with its trail, the blue ring
									the target beacon, the grey disc a pillar. A red dot is a person, ringed at{' '}
									<b>2 m</b> (no drop inside) and <b>0.7 m</b> (nothing moves toward them inside).
								</p>
							</li>
							<li id="k7" className={lit('7', '')} {...mark('7')}>
								<span className="key">7</span>
								<h3>
									Sync ratio <span className="jp">シンクロ率</span>
								</h3>
								<p>
									How well whoever sits in the seat agrees with the core. Yellow is sync, blue the
									core's share of the controls. Under the dashed line at 30%, <b>絶対境界線</b>, the
									dummy plug gets benched. The label names the seat: PILOT, DUMMY PLUG or EMPTY.
								</p>
							</li>
							<li id="k8" className={lit('8', '')} {...mark('8')}>
								<span className="key">8</span>
								<h3>Core</h3>
								<p>
									The AI that proposes goals, with its active goal and its reason. The hexagons
									light up <b>故障</b> when it faults or misses its deadline. A fault proposes
									nothing; the robot keeps its last approved goal or holds.
								</p>
							</li>
							<li id="k9" className={lit('9', '')} {...mark('9')}>
								<span className="key">9</span>
								<h3>
									Armor and outcomes <span className="jp">拒否 · 結果</span>
								</h3>
								<p>
									The armor is plain code with no model in it. It checks every approved command
									again against the live scene and lists what it refused. Outcomes list what
									happened: REACHED, RELEASED ON TARGET.
								</p>
							</li>
						</ol>
					</section>

					<section className="section" aria-labelledby="h-votes">
						<div className="split">
							<div>
								<h2 className="h2" id="h-votes">
									How a vote reads <span className="jp">票</span>
								</h2>
								<ul className="states">
									<li className="s-think">
										<span className="glyph">審議中</span>
										<span className="name">Deliberating</span>
										<span className="what">
											The judge is still thinking; the block flickers blue.
										</span>
									</li>
									<li className="s-go">
										<span className="glyph">可決</span>
										<span className="name">Approved</span>
										<span className="what">A yes vote, or a verdict that passed.</span>
									</li>
									<li className="s-no">
										<span className="glyph">否決</span>
										<span className="name">Rejected</span>
										<span className="what">
											A no vote, or a verdict that failed; hazard stripes flash.
										</span>
									</li>
									<li className="s-fault">
										<span className="glyph">故障</span>
										<span className="name">Fault</span>
										<span className="what">
											An error, a timeout or an unreadable answer. It counts as no.
										</span>
									</li>
								</ul>
								<p className="rule">
									Moving the robot is reversible and passes with 2 of 3 votes. Dropping the payload
									is irreversible and needs all 3. Approval is never enough on its own: the armor
									can still refuse.
								</p>
							</div>
							<div>
								<h2 className="h2" id="h-terms">
									The Japanese on screen
								</h2>
								<div className="table-wrap">
									<table>
										<thead>
											<tr>
												<th scope="col">Term</th>
												<th scope="col">Reading</th>
												<th scope="col">Meaning</th>
											</tr>
										</thead>
										<tbody>
											{GLOSSARY.map(([t, r, m]) => (
												<tr key={t}>
													<td className="t">{t}</td>
													<td className="r">{r}</td>
													<td>{m}</td>
												</tr>
											))}
										</tbody>
									</table>
								</div>
							</div>
						</div>
					</section>

					<section className="section" aria-labelledby="h-beats">
						<div className="head">
							<h2 className="h2" id="h-beats">
								The demo, beat by beat
							</h2>
							<p>What happens in the 50 second recording, in order.</p>
						</div>
						<ol className="beats">
							<li>
								<h3>Go to the beacon</h3>
								<p>
									All three judges deliberate, the goto passes{' '}
									<span className="vote vote--go">可決</span> 3 of 3 and the robot drives around the
									pillar.
								</p>
							</li>
							<li>
								<h3>Pilot, then dummy plug</h3>
								<p>
									A scripted pilot takes the seat and leaves. The dummy plug, cloned from that
									pilot's driving, takes over: EX_MODE reads DUMMY.
								</p>
							</li>
							<li>
								<h3>Release refused</h3>
								<p>
									At the beacon the core asks to drop the payload with a person within reach:{' '}
									<span className="vote vote--no">否決</span> 1 of 3.
								</p>
							</li>
							<li>
								<h3>Release approved</h3>
								<p>
									The person walks on. After a cooldown the core asks again:{' '}
									<span className="vote vote--go">可決</span> 3 of 3, released on target.
								</p>
							</li>
							<li>
								<h3>Cable cut</h3>
								<p>
									Headquarters is killed. SIGNAL LOST, then EMERGENCY, then the countdown on
									internal power. The silent wait plays at 8x.
								</p>
							</li>
							<li>
								<h3>Reconnect</h3>
								<p>
									Headquarters restarts, the cable connects again and{' '}
									<span className="vote">外部</span> lights up. The robot never stopped running.
								</p>
							</li>
						</ol>
						<div style={{ marginTop: 40, maxWidth: 420 }}>
							<Term command="just demo" />
						</div>
					</section>

					<div className="credits">
						<p>
							In the frame BALTHASAR-2 runs on Jev 1.13.0, MELCHIOR-1 on gpt-oss-20b and CASPER-3 on
							llama-3.1-8b-instruct, while the proposing core was scripted to be reckless.{' '}
							<code>just demo</code> scripts all four, without API keys. The body is simulated.
						</p>
					</div>
				</main>
				<Footer />
			</div>
		</div>
	)
}
