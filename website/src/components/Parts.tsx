/** The canon names and the modules that carry them, as README.md's table of parts has them. */
const PARTS = [
	{
		name: 'MAGI',
		jp: 'マギ',
		code: 'magi',
		text: 'Three judges on three model families. Two votes for reversible goals, all three for irreversible ones.',
	},
	{
		name: 'Core',
		jp: 'コア',
		code: 'core',
		text: 'Proposes the next goal. Its journal belongs to one pilot and outlives any backend.',
	},
	{
		name: 'Entry plug',
		jp: 'エントリープラグ',
		code: 'plug',
		text: 'Pilot input over UDP, the sync ratio, and a recorder that logs every tick.',
	},
	{
		name: 'A10 nerve connection',
		jp: 'A10神経接続',
		code: 'gamepad/',
		text: "A game controller as the pilot's hands. Contact, a person close by and the armor's strain come back as rumble.",
	},
	{
		name: 'Dummy plug',
		jp: 'ダミープラグ',
		code: 'plug/dummy.v',
		text: "The pilot's driving style as a small network. It loses the seat when it falls out of sync.",
	},
	{
		name: 'Restraint armor',
		jp: '拘束具',
		code: 'armor',
		text: 'The only thing that holds the body: speed, acceleration, geofence, distance to people, eject. No model inside.',
	},
	{
		name: 'Umbilical cable',
		jp: 'アンビリカルケーブル',
		code: 'umbilical',
		text: 'The link to HQ. Cut it and the unit runs five minutes on internal power, then holds.',
	},
	{
		name: 'LCL',
		code: 'lcl',
		text: 'Plain data every layer is immersed in, so any transport can carry it.',
	},
	{ name: 'Eva', jp: 'エヴァ', code: 'body', text: 'The robot API: sense, actuate, effect, halt.' },
]

/** The landing page's map of the parts: each canon name, its Japanese and the module that is it. */
export function Parts() {
	return (
		<section className="section" id="parts" aria-labelledby="h-parts">
			<div className="head">
				<h2 className="h2" id="h-parts">
					The parts <span className="jp">構成</span>
				</h2>
				<p>
					Cut along the lines Evangelion uses for an Eva. Each canon name is a module in the code.
				</p>
			</div>
			<ul className="parts">
				{PARTS.map((p) => (
					<li key={p.name}>
						<div className="parts__title">
							<h3>{p.name}</h3>
							{p.jp && <span className="jp">{p.jp}</span>}
						</div>
						<code>{p.code}</code>
						<p>{p.text}</p>
					</li>
				))}
			</ul>
		</section>
	)
}
