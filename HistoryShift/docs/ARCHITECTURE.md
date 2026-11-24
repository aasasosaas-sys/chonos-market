# JIDAI SHIFT — アーキテクチャ（Godot 4.5 / GDScript / Forward+ / Jolt）

ゲームの流れ: タイトル → 共通テスト（解答は確定） → 採点ハブ → 誤答を選んで時空跳躍 → 該当時代のオープンワールドでミッション → 改変（連鎖） → ハブ → … → 満点でエンディング（改変の組み合わせから自動合成）。自由探索モードあり。

## ディレクトリ
```
data/*.json           問題・ミッション・連鎖ルール（tools/SCHEMA.md）
assets/polyhaven/     CC0 テクスチャ (textures/<key>_diff|_nor_gl|_rough.jpg) と HDRI (hdri/sky_<day|clear|hazy|evening>.hdr)
                      models/<id>/<id>.gltf は tools/download_assets.py で任意取得（無くても動くこと）
assets/fonts/         Noto Sans JP / Noto Serif JP (OFL)
scripts/core/         game.gd (autoload "Game"), history_db.gd, history_state.gd, main.gd
scripts/world/        ワールド生成（担当: world）
scripts/player/       プレイヤー・カメラ・銃・乗り物・エフェクト（担当: gameplay）
scripts/mission/      セッション・ミッション進行・敵・NPC・町人・手配度・HUD（担当: gameplay）
scripts/ui/           flow.gd と各画面（担当: ui）
tests/                ヘッドレステスト・スクリーンショット
```

## 共通ルール
- 衝突レイヤ（Game 定数）: 1 WORLD(地形・建物などの静的物), 2 PLAYER, 3 ENEMY(値4), 4 CIVILIAN(値8), 5 VEHICLE(値16), 6 PROP(値32)
- グループ: "explosive"（撃つと爆発: RigidBody3D に scripts/player/explosive.gd）, "physics_prop", "landmark"
- 単位はメートル。Y上。ワールド原点がマップ中央。
- 日本語フォントはテーマ（assets/theme.tres）で全UIに適用済み。
- `Game.input_blocked` が true の間、ゲームプレイ入力は無視される（UI 側が設定）。
- `Game.lock_mouse(bool)` でマウスキャプチャ切替。

## Game (autoload) API
```gdscript
Game.db : HistoryDB      # .eras, .questions(年代順), .by_id, .rules, .get_era(id), .mission_for(q, choice), HistoryDB.landmark_name(era, key)
Game.state : HistoryState # world_choice(q), answer(q), set_answer(q,c), is_correct(q), is_altered(q), correct_count(), score(), perfect(),
                         # apply_change(q, c, cause)->Array[{question,from,to,cause,depth}], predict_ripple(q,c)->Array[{question,to,note}],
                         # compose_ending()->[title, text], exam_submitted, alterations, restorations, history_log, save(), reset_all()
Game.world / Game.player / Game.input_blocked / Game.lock_mouse()
```

## EraWorld（担当: world）— `scripts/world/era_world.gd`
```gdscript
class_name EraWorld extends Node3D
static func build(era: Dictionary, year := 0, hist := {}) -> EraWorld   # era = Game.db.get_era(id)。add_child は呼び出し側。
                                                    # year = 時代の中の年（0 = 年の指定なし）、hist = {"ruins": 前の年に壊した建物}（下の「時代の中の年」）
var era: Dictionary
var half_size: float          # 遊べる範囲は [-half_size, half_size]（約 600）
var water_level: float
var player_spawn: Vector3
func landmark_pos(key: String) -> Vector3           # 地表の位置
func height_at(x: float, z: float) -> float
func random_ground_point_near(center: Vector3, radius: float, rng: RandomNumberGenerator) -> Vector3  # 水上・建物上を避ける
func set_beacon(key: String, on: bool)              # 目標地点の光の柱
func vehicle_spawns(kind: String) -> Array          # Array[Transform3D]。"horse" "car" "plane"（plane は滑走路/平地）
func street_points() -> Array                       # 町人が歩く地点 Array[Vector3]
func set_time_of_day(hours: float)                  # 任意（0-24）
```
WorldEnvironment・太陽（DirectionalLight3D）・空・霧・ポストエフェクトは EraWorld が持つ。カメラは gameplay 側。

## Session（担当: gameplay）— `scripts/mission/session.gd`
```gdscript
class_name Session extends Node3D
signal completed(changes: Array)      # ミッション成功時。apply_change 済みの変化リスト
signal failed(reason: String)
signal aborted
static func start_mission(q: Dictionary, choice: int) -> Session   # ワールド・プレイヤー・HUD・ミッション進行を生成
static func start_free_roam(era_id: String, year := 0) -> Session   # year 0 = 時代の代表の年（data/eras の default）。ミッションは問題の年
static func start_backdrop(era_id: String) -> Session              # タイトル背景用（カメラが周回、操作なし、HUD なし）
func end()                                                         # 片付け（queue_free）
```
呼び出し側（flow.gd）が `add_child(session)` する。Session 内で HUD・ポーズメニュー（再開/中断）・死亡時リトライを処理する。

## Flow（担当: ui）— `scripts/ui/flow.gd`
main.gd が `Flow` ノードとして生成する。タイトル・試験・採点ハブ・ブリーフィング・ワープ演出・改変結果（連鎖表示）・エンディング・改変ログ・設定・クレジットを担当。Session を生成/破棄して画面を切り替える。

## 破壊システム（担当: world/gameplay）— `scripts/world/destruction.gd` ほか
- 生成時: `Architecture.begin_unit(kind, xf)/end_unit()` で建物・塀区画・灯籠・船・橋区画などを「破壊ユニット」として記録（`EraWorld.unit_defs`）。
  ジオメトリは従来どおり結合メッシュに残り、UV2 にユニット ID を焼く（描画コールは増えない）。土台（foundation）は壊れない。
- `Destruction.attach(world)` が各ユニットを `Destructible`（StaticBody3D, layer WORLD, group "destructible"）に変換し、
  状態テクスチャ（global uniform `destruct_tex`）でシェーダが 隠す/焦げ/ひび/燃えさし/切断（廃墟の高さ）を描く（`shaders/destruct.gdshaderinc`）。
- 被害: `take_hit(amount, team, point, dir)`（弾）/ `ram(speed, vel, mass_k)`（乗り物）/ `Destruction.blast_at(tree, pos, r, dmg, team, fire)`（爆発。`Effects.explosion` が自動で呼ぶ）。
  段階: ひび → 屋根崩落（瓦が滑り落ちる）→ 倒壊（`Fracture.slice` で元メッシュを格子に切った破片 RigidBody＋瓦礫の山＋低いコリジョン）。
- 木は `EraWorld.tree_defs`（MultiMesh のインスタンス）を倒す。火災は木造に延焼（同時 14 棟・ランドマークごと 36 回まで）。
- 破片 layer は `Game.COLLISION_DEBRIS`(64)。プレイヤー・町人とは当たらない（町人は爆風でも倒れず逃げる）。
  例外：設定「民間人への危害（成人向け）」（既定オフ・教育版では無効）がオンなら、町人はプレイヤーが原因の被害で倒れる（瓦礫は町人が近くの建物の倒壊を見て判定。`scripts/core/civil_harm.gd`・`scripts/mission/civil_runtime.gd`・`data/chaos_civil/`、tools/SCHEMA_V2.md）。
- `Game.chaos_event(kind, id, info)`: kind = destroy / sink / fire / bridge / block。id はランドマークのキー（道沿いは "town"、川の橋は "river"、block の橋は橋グループ ID）。
  info = {era, pos, type, cause("player"|"player_indirect"|"enemy"|"world"), ...}
- ツール（`scripts/player/destruction_tools.gd`）: 1 銃 / 2 焙烙玉 / 3 火薬樽・ダイナマイト / 4 大筒・野砲（設置→砲撃）/ 5 棒火矢、G で焙烙玉、ホイールで切替。

## 実寸の船（担当: world）— `scripts/world/ships/`
- データ: `data/ships/<id>.json`（調査）＋ `"layout"`（ゲーム用: 船型・部品・部屋の位置ヒント・浸水の設定）。`sosen.json` は ming_junk の変種（平安の宋船・仮）。
  座標は船ローカル（水線中央が原点、船首 -Z、右舷 +X）、部品の位置 `s` は水線の船首からの距離 m。
- `ShipData`（読込＋配置計画: 甲板の分類 weather/internal/super、天井高 2.15m 未満は広げる、部屋の配置、階段、区画・水密扉・注水弁）
  → `ShipExterior`（船体・上甲板・部品、常に表示）／`ShipInterior`（船内、近づくと数フレームに分けて生成・離れると解放）／`ShipProps`（key_props の語から小道具）。
- `Ship`（AnimatableBody3D の `ShipBody` を持つ）: 被害 `on_hit / on_blast / on_direct_blast / on_ram / on_ignite`、E で水密扉・注水弁・ポンプ・舷梯、
  小さめの船は舵（`ShipHelm`、F）で操船。沈没で `Game.chaos_event("sink", "port", {type:"ship", ship, name, pos, value, cause, era, landmark})`。
- `ShipFlood`: 区画ごとの水量、破孔流入 q=Cd·A·√(2gΔh)、扉・隔壁上端の流れ、ポンプ（缶室浸水で停止）、沈下・トリム・GZ 曲線による傾斜/転覆、
  木造の延焼と焼け抜け、空母格納庫の誘爆、火が弾火薬庫へ（注水で防げる）。
- `ShipYard`（EraWorld の子、`layouts.gd` の `_port_layout` 末尾の 1 行で配置）: 爆発の通知（`Destruction.blast_at` 内の 1 行 → `blast_all`）、
  泳ぎ・息・沈む船からの脱出、海面マスク（`water.gdshader` の dry_* uniform）、状態表示、`ShipLaunch`（小舟・内火艇）。
- 箱庭との縮尺: 地形は ±220m、岸から境界まで 30〜40m しかないので、喫水の深い船（大和・赤城・加賀・氷川丸・三笠・サスケハナ等）は実寸のまま
  境界の外の沖に錨泊させ、その船の周り 60m にいる間だけ `EraWorld.half_size` を広げる（小舟で渡る）。浅い船は岸近くに桟橋つきで置く。
- テスト: `tests/test_ships.tscn`（ヘッドレス: 全船の組立・自沈/爆薬/弾火薬庫/放火の早回し）、`tests/shot_ships.tscn`（外観・船内・沈没の連続写真）。

## 屋内（担当: world）— `scripts/world/interiors/`
- 生成時: 建物の壁は `Architecture.shell()`（外から見た姿は従来の箱と同じ中空の壁体＋天面＋室内側の天井）で作り、入口の開口を抜く
  （`slab()` が見た目と当たり判定の両方を抜く。窓の開口は見た目だけ）。土台の段は `entry_steps()`（見た目の段＋坂の当たり判定）。
  外側の帯（下見板・胴蛇腹）は `band()`（天面なし＝室内に面が出ない）。いずれも破壊ユニットの begin/end の中で作るので、
  破片・状態テクスチャ・ユニットのコリジョンに自動で含まれる。
- 登録: `Architecture.reg_interior(type, xf, floors, doors, opts)` → `EraWorld.interior_defs`。
  floors = [{y, rect(局所 xz), h, hole(天井の吹き抜け), stair{a,b,w}, win(窓)}]、doors = [{p, n, w, h, out}]。寸法は外観と同じ。
- `WorldInteriors`（EraWorld の子）: プレイヤーが 25m 以内に来た建物だけ `InteriorBuilder`＋`InteriorKits`/`InteriorKitsModern` で内装を作り、
  60m 超で外す（6 棟までプール、同時 10 棟）。1 棟 = MeshInstance 1 つ＋StaticBody 1 つ。実ライトは近い順に 4 灯まで（無影）、他は発光材。
- キット（時代×用途）: pit 竪穴住居 / takayuka 高床倉庫 / raised_hall 祭殿 / shinden 寝殿造 / palace・daigokuden / temple 本堂 / pagoda / kinkaku /
  shrine 拝殿 / shoin 書院造 / goten 御殿 / machiya 町家（2 階）/ nagaya 長屋 / chaya 茶屋 / minka・farmhouse / kura 土蔵 / storehouse /
  castle 天守（全層・階段・連子窓）/ yagura / yokan 洋館 / office・office_showa / bank / station 駅舎 / factory 製糸場 / warehouse(_showa) /
  school / diet 中央広間 / showa_shop・showa_house / danchi 2DK / hangar / tower。典拠は `data/interiors/kits.json` の basis。
- 破壊との連動: 屋根崩落（stage>=2）・炎上で入口を塞ぐ（中にいなければ内装も消す）。中にいる時に燃えたら屋内に炎と煙（体力 3 割までの微ダメージ）。
  倒壊（`Destruction.destroy_unit` → `on_destroyed`）で内装を捨て、中のプレイヤーは入口の外へ押し出して最大 45 のダメージ（即死させない）。
- カメラ: `CameraRig.indoor`（WorldInteriors が設定）で腕を短く・低く、壁・天井の手前で止める（各階の天井に当たり判定あり）。
```gdscript
EraWorld.get_interior_points(unit_id) -> Array[Vector3]       # 屋内の NPC 地点（内装を作っていなくても返す）
EraWorld.get_interior_spots(unit_id) -> [{pos, yaw, floor, role}]   # role: stand/sit/work/guard/scene
EraWorld.find_interior(tag) -> int                            # "honnoji" "omiya" "tenshu" "rokumeikan" "shimbashi" "diet" ...（kits.json の scenes）
EraWorld.find_interiors(type, landmark) -> Array[int]
EraWorld.get_interior_info(unit_id) -> {type, name, basis, floors, tags, doors:[{pos, out, normal}], loaded, blocked}
EraWorld.ensure_interior(unit_id, pin) / release_interior(unit_id) # 上階に NPC を立たせる前などに先に作る
EraWorld.interior_at(pos) -> int
```

## 技能・持ち物・製作（担当: gameplay）— `scripts/core/skills.gd` ほか
主人公は現代の高校生なので**素手で始まる**。武器は過去で手に入れる（倒した兵の落とし物・蔵/武器庫を探る＝盗み・店で買う・人物に譲ってもらう・工房で作る）。
- データ: `data/crafting/items.json`（品：種類・基本値・史実の時代 `era`・値段（文）・時代錯誤の歴史効果 `tech`）、`recipes.json`（場所・時代・必要技能・補助技能・材料・`anachro`＝過去で作るのに要る未来の技能）、
  `workshops.json`（弟子入りできる工房・学校 19 か所：時代・名所・教われる技の上限・稽古・手伝い・史実の根拠 `basis`）、`trade.json`（時代ごとのお金・店・蔵・兵の落とし物）。
- `Game.profile : PlayerProfile`（`scripts/core/player_profile.gd`）: 技能 18 種（0〜100）・持ち物（個体＝武器：品質・耐久・装填数／束＝材料・弾・爆弾：数と平均品質）・所持金（文。1両=4000文=1円）。
  `user://profile.json` に保存（歴史のセーブとは別）。時代をまたいで、ハブに戻っても持ち越す。新しいゲーム・リセットで初期化。
  `level(id)`（技術完全習得モードなら 100）/ `train(id, amount, cap)`（弟子入り）/ `practice(id, amount)`（使うだけで上がる。50 まで）/ `lend()`・`return_loans()`（貸与品は保存しない）。
- `Skills`（純関数）: 技能→能力の式。剣術・槍術（威力 0.7〜1.3 倍・振りの時間 1.35〜0.85 倍・受け 30〜85%・受け流しの猶予・刃の傷み）、射撃（散らばり・反動・装填・不発）、弓術（引き・矢の勢い・揺れ）、
  自動車運転（ハンドル反応・グリップ・ふらつき・加速）、乗馬（速さ・小回り・落馬率）、飛行機操縦（旋回・揺れ・失速速度・着陸できる速さ/降下率）、操船（`boat_*`：船側が使う）、医術（回復）、話術（説得 +0〜2・売り買い）、古文読解（書状の成功率）、建築（爆薬の威力）。
- `Crafting`: 品質 q = 0.15＋0.6·主技能＋0.15·補助技能＋0.3·(材料の質−0.5)＋0.2·(仕上げの出来−0.5)。等級 粗悪/並/上/名工。品の能力値も q から（刀：威力・耐久・振りの速さ、銃：精度・不発・装填・反動、弾薬・爆弾：威力と不発）。
- `PlayerArms`（Player の子）: 素手（拳・溜めて蹴り）／刀・槍（軽い振り・長押しの強い振り・右クリックで受け／受け流し・耐久）／弓（引いて放つ）／銃（装填・時代の連射速度・火縄銃は一拍おくれて発火・不発）。
  破壊ツールの 2〜5（焙烙玉・手榴弾・火薬樽・ダイナマイト・大筒＋砲弾・棒火矢）は持ち物を消費する。`ThrownBomb.power/dud`・`Shell.power/dud`。
- `Enemy`: 中世〜江戸の兵の一部は刀・槍で斬りかかる（振りかぶりの間に受けると受け流せる）。倒すと `LootDrop`（武器・弾・銭）。修正力は落とさない。
- `CraftWorld`（Session の子）: 自由探索で工房・店・蔵を名所のそばに置く（`CraftStation`、E で開く）。Tab / I / Back で時空鞄（`CraftUI`：持ち物・技能・製作・メモ）。
  稽古は `Minigame`（hammer/heat/assembly/mix/target）か `CourseLesson`（馬・車・飛行機で目印を回る）。
- 歴史: 動詞 `teach`（人物・職人に技を教える：`HistoryActors.TEACH` × 技能/100 × 影響力）、`anachronism`（この時代にまだない品を渡した・落とした・職人の前で作った：`items.json` の tech × 何時代ぶん未来か（上限3）× 原因の重み）。
  どちらも一般則（手作りルールは追加していない）。説得・未来を語るは `info.skill_bonus`（話術）を信頼に足す。
- ミッション: 使える武器を持っていなければ、開始時にその時代の武器を貸与（`Session.MISSION_KITS`：縄文〜室町は弓＋刀、戦国・江戸は火縄銃＋刀、明治・昭和は三八式）。終われば返す。
- 設定: 「技術完全習得モード」（技能 100・レシピ解禁、学んだ値は残る）、「最初から武装」（時空銃＋爆薬を貸与）。どちらも既定はオフ。
- テスト: `tests/test_skills.gd`（ヘッドレス：式・製作・保存・時代をまたぐ持ち越し・完全習得・teach/anachronism・近接/受け/装填/落とし物/貸与）、`tests/shot_skills.tscn`（工房・稽古・製作・持ち物・近接の写真）。

### 知識の木と産業（主人公が自分で産業革命を起こす）— `scripts/core/knowledge.gd`・`scripts/mission/facility.gd`
- データ: `data/crafting/knowledge.json`（10 分野・39 ノード：冶金 たたら→反射炉→洋式高炉→製鋼／機械 からくり→旋盤→互換性部品→精密機械／動力 水車→蒸気機関→鉄道・内燃機関／
  化学 火薬→硫酸・ソーダ→化学肥料・石油精製／電気 エレキテル→電池→電信→発電／数理 和算→測量・天文→航海術／医学 漢方→蘭方→種痘→細菌学／繊維 手織→機械紡績・器械製糸／
  造船 和船→洋式帆船→蒸気船・飛行機／経営 複式簿記→株式会社・学校。各ノード: prereq・師のいる時代 era・schools（工房 id か学問所 id：佐賀藩精錬方・釜石の高炉・長崎海軍伝習所・天文方・
  からくり儀右衛門の工房・本草学者の工房・工部大学校・鉄道寮・富岡製糸場・伝染病研究所・国立銀行・八幡製鉄所・造幣寮…）・modern（現代の常識）・book・vars・basis）。
  `data/crafting/buildings.json`（16 施設：水車小屋・町の工房・たたら場・鉱山/炭鉱・反射炉・洋式高炉・機械工場・紡績工場・製糸場・化学工場・洋式造船所・発電所・鉄道・電信線・銀行・学校）。
- 状態 `PlayerProfile.knowledge {id: {p, m}}`・`permits {era: true}`・`buildings [rec]`（すべて保存）。はじめから現代の常識（modern）の原理だけ知り、`kyokasho`（未来の教科書）を持つ。
  習熟は 師（100 まで）・実験（60 まで）・施設の稼働（80 まで）。前提の習熟 +30 を超えられない。技術完全習得モードではすべて原理○・習熟 100。
- 建設（自由探索・名所から 90m 以内）: 知識の習熟・建材・費用・働き手・動力（水車は村/寺/港、蒸気は蒸気機関の品と毎回の石炭）・支配者の許し（ruler/official/reformer の人物を説得するか冥加金）。
  施設は生産（原料→品・稼ぎ）・職人の腕（「職人に教える」で上がる）・拡張（規模 3 まで）・製作の場所（`station`）。離れていた間の分は最大 30 回ぶん。
- 歴史への知らせ（ほかの担当が使える形）:
  `Game.chaos.act("industry", <buildings.json の id>, {"landmark": <名所キー>, "scale": 1〜3, "mult": <学校は 1+知っている原理/10>, "bonus": bool})`
  → 行動 `{verb:"industry", target, landmark, scale, mult, bonus, era, seq}`。効果は施設の vars ×(1+0.5(scale−1))×mult を、その時代の年に歴史パラメータへ（WarModel の複利で 1941 年の柱に効く）。
  同じ時代・同じ名所・同じ規模は一度だけ。知識を教える（`teach`、skill に知識ノード id）は knowledge.json の vars。同じ相手に同じ知識は一度だけ（`ChaosTracker._done_before`）。
  生産が `Knowledge.RUN_MILESTONE`（12）回に達すると `stage: "run"`・mult 0.5 でもう一度だけ知らせる（稼働する工場を見て真似る者が出る）。
- 市場: `buildings.json` の `markets`（品ごとの時代の需要倍率と史実の根拠。例 生糸は開港後の明治 ×1.4、玉鋼は廃刀令後 ×0.4）。
  施設画面の「問屋に卸す」＝ `Knowledge.market_price/market_sell`（品の値×0.6×需要×売れ残り（1つ 4%・最低 40%・30 秒で 1 つ分戻る）×話術）。
- 操船: `Player.apply_sailing(helm)` が乗船時に `ship.sd.pilot` の vmax・turn を操船の技能の倍率で置きかえる（ships/* は変えない）。舵を取って 40m 進むごとに操船の稽古。

## 時代の中の年（担当: gameplay/world）— `data/eras/<era>_timeline.json`・`scripts/core/era_timeline.gd`・`scripts/world/timeline_world.gd`
箱庭は時代全体の静止画ではなく、選んだ年の姿になる（徳川家康と坂本龍馬が同じ年に並ばない）。
- 時点（points）：自由探索で選べる年（時代選択のあとに年を選ぶ。`EraPicker.open_years` → `Flow.start_free_roam(era, return_to, year)`）。
  ミッションは問題の年（`Session.mission_year(q)`）に降り立ち、その年に効いている時点（その年以前で最も新しい時点）の設定を使う。
  各時点：label・desc（年の入った史実）・basis・guard（護衛の名）・crowd（町人の装いの比率 → `Humanoid.outfit_for`）・enemy_outfit・crowd_n・events・ruin。
- 人物：`EraTimeline.actor_present`＝活動開始年−10（かつ 15 歳以上）〜没年。あなたが倒した（kill/escort）年から先にはいない（前の年にはいる）。
  救った（protect・特効薬）人は史実の没年の後も（生年+80 まで）。顔の年齢区分（`Figures.age_at` → AnimeFace の young/adult/elder）と名札の年齢。
  予定（schedule）・合戦・国家事業は、その年に最も近い時点（予定は人物がいる時点）に現れる。
- 船：`ShipYard.ships_for(era, year)`（timeline の ships：朱印船 1604–35、サスケハナ 1853–68、咸臨丸 1857–71、三笠 1902–23、赤城 1927–42、加賀 1928–42、大和 1941–45、氷川丸 1930–）。
- 建物：`units`（その年にまだ無い・もう無い：江戸城天守は 1657 年から天守台だけ、明治の煉瓦建築は銀座煉瓦街 1872 年以後…）と時点の `ruin`
  （明暦の大火 1657・関東大震災 1923・東京大空襲 1945 の直後の焼け跡）を `TimelineWorld.apply` が組み上げ後に当てる（破片・通知なし。ユニット ID は年によらず同じ）。
- 歴史：自由探索の行動は選んだ年を `year` に記録し（`ChaosTracker.active_year`）、一般則の効果はその年に起きる（`HistoryActors.resolve`。人物の貢献など年の決まった史実はその年のまま）。
  自由探索で壊した建物・沈めた船は `HistoryState.ruins[era]`（保存される）に年つきで残り、同じ時代のその年以後の時点でも壊れたまま（家・蔵などは `REBUILD_YEARS` 後に建て直される）。
- 検査：`tests/test_timeline.tscn`（生没の外に出ない・船・ミッションの年・前の年に壊した建物・**手作りの道（揺らぎのルール・人物の動詞・予定・合戦・事業・各問題の「未来を語る」相手）が
  どこかの時点で必ず起こせる**）。写真：`tests/shot_timeline.gd -- edo 1615,1657,1853`。

## 歴史の見た目（担当: world/ui）— `data/visuals/history_visuals.json`・`scripts/core/history_visuals.gd`・`scripts/world/history_dressing.gd`
箱庭とハブは「その世界の歴史が、その時代のその年に史実とどれだけ違うか」で姿が変わる（ミッションごとの手作りはしない）。
- 状態：`HistoryState.snapshots`（設問ごとの状態）から `HistoryVisuals.state_at(era, year)`、史実は `_simulate_war({}, [], [])` を一度だけ計算して比べる。
- 軸（axes）：industry（tech・economy・commerce）/ west（open_west・education・tech）/ prosperity / military。軸×years_per_point = lead（史実より何年早いか。負は遅い）。
- 規則（JSON）：features（史実で日本に現れた年 year・世界で可能になった年 earliest・史実でそこに実在したか real／min_lead）、absent（遅れた世界でまだ無いもの・swap で町家に）、
  crowd（町人の装いの比率：`EraTimeline.crowd_outfit` → `HistoryVisuals.adjust_crowd`）、navy（国際的地位が史実より上 → 港に帆船の軍船／装甲艦／戦艦）、
  war（昭和 1945 年以後：空襲の被害の倍率・本土決戦の追加の焼け跡・占領／講和／休戦／戦勝の看板と旗・装い）、capital（首都が別の町 → 都に高札・庁舎の看板）、present（2026 年の町）。
- 生成：`Session.world_history(era, year)` が `{"ruins", "vis": HistoryVisuals.profile(...)}` を EraWorld に渡す。`WorldLayouts.build_all` の最後で `HistoryDressing.build(w, a)`
  （製糸場・製鉄所・鉄道（狭軌の線路・停車場・機関車）・電信・ガス灯・アーク灯・港の艦隊・看板、町家⇔煉瓦の建て替え）。普通の破壊ユニットなので壊せる・燃える・入れる。
  追加は元の建物の後ろの ID なので、元の ID は歴史によらず同じ。`TimelineWorld.apply` が `HistoryDressing.after`（建て替えの元・遅れてまだ無い建物を消す）と
  `HistoryDressing.ruin_rules`（空襲の被害を戦争の帰趨で）を呼ぶ。hist に vis が無ければ従来どおり。煙は最大 4 本、看板は Label3D。
- ハブ（2026年）：`Flow.show_hub` は `HubSession`（`scripts/mission/hub_session.gd`：`PresentWorld`＋Player）を出す。研究所の操作卓で E（または Esc）→ 採点ハブの画面
  （問題の一覧・ブリーフィング・時代選択・自由探索）。画面右上「研究所を歩く」で戻る。採点直後（reveal）は一覧を先に出す。`Flow.use_hub_3d = false` で従来の 2D だけ。
  `PresentWorld`（`scripts/world/present_world.gd`）：style modern / prewar / blocks / wood、lang ja_en / ja / ja_old（縦書き）、首都の名（駅・看板）、豊かさ（建物の高さ）、記念碑。
- 検査：`godot --headless --path . res://tests/test_history_visuals.tscn`（状態を切り替えて箱庭・町人・ハブ・Flow が変わる）。
  写真：`xvfb-run -a godot --rendering-driver vulkan --path . --resolution 1280x720 res://tests/shot_history_vis.tscn -- meiji showa edo hub`。

## 音（担当: gameplay）— `scripts/audio/`・`assets/audio/`・`tools/audio/`
- 素材: `assets/audio/{footsteps,sfx,ambience,music,ui}/*.ogg`（540 ファイル・203 key）。Kenney の CC0 パックを加工したもの＋`tools/audio/*.py`（numpy/scipy）で合成したもの。
  一覧と出典は `assets/audio/ASSET_CREDITS.txt`。key の表は `scripts/audio/sound_manifest.gd`（生成物。`python3 tools/audio/build.py --kenney <dir>` で作り直す）。
- `Audio`（ルート直下の AudioHub）: バス Master / Music / SFX / Ambience / Voice（設定画面の音量）。`Audio.play(key)` 2D、`Audio.play_at(key, pos)` 3D
  （接頭辞ごとの距離減衰・ピッチ±と音量±の揺らぎ・key ごとの同時発音数・40 音のプールで遠く優先度の低いものから置きかえ・聞こえない距離は鳴らさない）、
  `Audio.loop_at(host, key)` 乗り物・火・導火線、`Audio.music(key)` BGM のクロスフェード。屋内は Ambience をローパス、SFX に残響（`Audio.set_indoor`）。ヘッドレスでは鳴らさない。
  旧 `Sfx` / `UISfx` は key を返す互換ラッパ。
- 足音 `Footsteps`（Player・町人・兵・人物・Npc・馬の子）: 移動距離で一歩（速さで歩幅）、走り・着地・泳ぎ、馬は歩様（常歩・速歩・駈歩・襲歩）の蹄。
  床材 `Surface.at(pos)`: 下向きのレイ → 形/ボディの meta "surface"（Architecture の土台・段、PresentWorld）／船（`Ship.surface_at`：木造は板、鋼船は上甲板の材・船内と上部構造は鋼）／
  建物の中（`WorldInteriors.surface_at`：`InteriorBuilder.finish` が記録した畳・板・土間・石・リノリウム・絨毯）／破壊ユニットの材／地形（道・広場は時代の舗装、田は泥、岸は砂、急斜面は砂利、昭和の山頂は雪）。
  足が水面より下なら水（海・川・`EraWorld.water_rects` の池・堀）。
- 環境音 `AmbienceDirector`（Session・HubSession の子）: 時代の季節（鶯・蝉・ひぐらし・鈴虫）、海までの距離（波）・川・森・田（蛙）・町人の数（ざわめき）・合戦・高さ（強風）・屋内・船（木のきしみ／鋼の機関）、
  一発の音（鳥・烏・鳶・鴎・梟・寺の鐘・犬・風鈴・拍子木・汽車と汽船の汽笛）、2026 年は研究所の機械音と往来。
  天気（下の「天気」）: 小雨・大雨・屋内の屋根の雨（木造＝瓦・板・茅／洋館・昭和の建物・鋼船＝トタン）・台風のうなり・雪のしじま。雨と雪の間は鳥・虫を黙らせ、
  雪はざわめきも吸う。雷は WeatherDirector が光ってから距離÷343 秒後に鳴らし、強風の日は突風（wind_gust）。
  足音は `Footsteps.weather_surface`（屋外だけ）：濡れた石・板・舗装＝step_wet、濡れた草＝step_wet_grass、土＝泥、積雪＝雪（`Surface.WEATHER`）。
- 検査: `godot --headless --path . res://tests/test_audio.tscn`（全 key の素材、コードが使う key の解決、床材の判定、Audio を有効にした再生経路の通し）。

## ルック（アニメ調の描画）— `shaders/`・`scripts/world/atmosphere.gd`・`era_styles.gd`
- 時代ごとのプリセット（`EraStyles._anime`）: 太陽の色・高さ、影色 `shade_color`、空・雲、漆喰の色味 `plaster_tint`/`wood_tint`/`roof_tint`、低い霞 `haze_*`、
  カラーグレーディング `grade`（`WorldAtmosphere.grade_lut` が 32³ の 3D LUT を作り `Environment.adjustment_color_correction` に。夜は `grade_night`）。
  平安＝春のパステル、戦国＝黄金色の夕刻、江戸＝澄んだ青の昼、明治＝暖かいセピア寄り、昭和＝夏の午後（入道雲・褪せたフィルム）。
- グローバルシェーダ変数: `toon_shade_color` `toon_params` `world_night` `world_sky_color` `world_sun_color` `world_wind`（風向き・強さ）`world_indoor`（屋内の度合い）。
- `toon.gdshaderinc`: セル 3 段（影は寒色・明部は日の色）、影の中の空の照り返し、明暗の境の色の転び、空色のリム。
- `building.gdshader`: `mat_kind`（1 漆喰 2 木 3 瓦 4 石 5 茅 6 布 7 畳）で手描きの塗り（色ムラ・雨だれ・裾の汚れ・木目・瓦の列と空の映り込み・石ごとの濃淡）。
  `instance uniform hs_indoor`（内装のメッシュ）で障子の透け・木と畳の暖色、外殻との z ファイティング回避。
- `post_anime.gdshader`: 輪郭線（遠景は空気の色へ）、凸の稜線のハイライト（粗さ 1.0 の草・葉・地形・人物には付けない）、光芒、太陽のグレア、周辺減光。
- 屋内: `WorldInteriors` がプレイヤーの出入りで `WorldAtmosphere.set_indoor` を 0→1 に補間（暖かい環境光・露出・灯りのにじみ）。
- 人物（MToon）: `_HsKind`（`AnimeChar._tag_materials` が VRM 読み込み時に設定。1 髪＝天使の輪 / 2 肌＝血色の帯 / 3 顔＝影を柔らかく / 4 目）、全員にリムライト、服は影の 3 段目。
- 被写界深度: `WorldAtmosphere.set_dof(world.env_nodes, 焦点距離)`（0 で無効）。検証は `tests/shot_visual.tscn -- <era> <tag> [shots]`。
- 材質キー（`WorldMaterials.get_mat`）の追加: `boards`（屋内の板の間。継ぎ目・板ごとの濃淡はシェーダ `mat_kind` 8 が描く。細い板を浮かせると輪郭処理の稜線ハイライトで白線になる）、
  `steel`（鋼船の船体・隔壁の軍艦色。空の映り込み控えめ）。屋内のガラス（`hs_indoor`）は外の景色（空・木立・地面）を描いた発光面で、白飛びしない。
- 白い布（MToon の服 `_HsKind` 0）: 淡い布ほど影を寒色に下げ、UV 上のしわの揺らぎで明暗の境を波打たせる。
- モーションキャプチャ（`assets/characters/mocap`）の腰の位置は `Humanoid._mocap_in_place` でその場・素体の腰の高さに直す（収録位置のずれで体が当たり判定から 1〜2m ずれていた）。
  待機は KayKit の `Idle_A`（`Mocap_Stand` は実は歩きの一部）。
- 自分で建てた施設（`Facility._build_visual`）は MeshKit＋建物シェーダ: 製糸場＝木骨煉瓦・瓦の切妻・越屋根（富岡製糸場）、機械工場＝鋸屋根、反射炉＝韮山の白い連双煙突、
  高炉＝石積み、銀行＝列柱と破風など。検証は `tests/shot_vis2.tscn -- facilities|ships <era> <tag>`。

## 天気（担当: world/gameplay）— `data/weather/`・`scripts/core/hist_weather.gd`・`scripts/core/kyureki.gd`・`scripts/world/weather_fx.gd`
史実の天気を、記録が遡れる深さに応じた層で決める（「出来れば遡れるだけの時代の天気」）。
- 日付: 時点ごとに事件の日（`data/weather/eras.json` の points：旧暦 `lunar` か西暦 `date`）。無い時点は時代の見た目の季節の代表日（season）。
  旧暦は `Kyureki`（Meeus の朔・太陽黄経、ΔT、冬至を含む月が 11 月・中気の無い月が閏月、1844 年からは定気、それまでは平気。日本時間の真夜中で日を区切る）で換算する。
  宣明暦（〜1684 年）は独自の定数のため 1 日ずれる月がある（ザビエル上陸 1549 年など）。表示は 1582 年 10 月 15 日より前がユリウス暦、季節の計算は先発グレゴリオ暦。
- 層（`HistWeather.lookup(era, year, jd)`）:
  1. 有名な日 `famous_days.json`：verdict（verified / documented / secondary / disputed / unverified）・basis・sources・HUD の一言 line・その日の移り変わり sequence。
     unverified と `apply:false` は上書きしない（本能寺の変・憲法発布の日）。文永の役は「論争中・台風ではない冬の嵐」、赤穂浪士の夜は「論争中」と表示する。
  2. 気候値 `regions.json`：地点（東京・鎌倉=横浜・京都・奈良・博多・名古屋・関ヶ原=岐阜）の月別の平年値（気象庁 1991〜2020 年：気温・降水量・降水日数・雪日数・雷・霧・台風の接近・梅雨入り/明け・風）。
     その日の天気は地点と日付の決まった乱数（数日周期でつながる天気図＋その日の揺らぎ。分布は経験分布で一様化し、雨の日の割合を平年値に合わせる）。
     前の 12 日から積雪と地面の濡れを持ち越す。気温が低いほど降水は雪になる。
  3. 代理指標による補正 `eras.json` periods / anomalies：完新世の温暖期・古墳寒冷期・京都の桜の満開日（Aono & Kazui 2008）による 3 月の気温・小氷期・
     東京の観測（1875 年〜）の都市化の分、飢饉の年（寛喜 1230〜31・天明 1783〜87・天保 1833〜38）の冷夏・長雨。昔ほど霧を増やす（fog_mult）。
  時代の地点：縄文〜奈良＝奈良盆地、平安・戦国＝京、鎌倉室町＝鎌倉（1185・1274・1281・1371 は博多）、桶狭間＝名古屋、関ヶ原、江戸〜昭和＝東京。
- 演出 `WeatherDirector`（Session の子、`HistWeather.live` に今の値を書く）: 目標へなめらかに移る（雨は十数秒・霧は数十秒）、雨の帯・突風の揺らぎ。
  雨筋（カメラに付いてくる GPUParticles3D、`shaders/weather_drop.gdshader`：風で斜めに伸びたカメラ向きの帯）、足元の地面に水はねの輪。屋根・木で粒を止める
  `GPUParticlesCollisionHeightField3D`＋当たった所のはね（サブエミッタ）は `WeatherDirector.roof_collision`（既定オフ：ソフトウェア Vulkan では高さの場が描かれず粒がすぐ消えたため。
  GPU で確かめてから有効にする。写真は `WX_HF=1`）。雪片（乱流でゆらぐ）。屋内では粒を止める。霧＝環境の深度霧・高さ霧。空＝`anime_sky` の overcast（雲底の筆ムラ・太陽と星を隠す）。
  稲光＝`world_weather.w` で `post_anime` が画面を照らす（空ほど強く）＋遠くの稲妻の帯。日差し＝`WorldAtmosphere.refresh_sun`（時刻 base_e × 天気 wx_e × 屋内 in_k）。
  色調＝Environment の彩度・明るさ・コントラスト、`world_sky_color`・`world_sun_color` を灰色へ。海の波（wave_amp）を荒らす。風＝`world_wind`（草・葉の揺れ、w は雨の強さ）。
- グローバルシェーダ変数 `world_weather`（x 地面の濡れ、y 積雪、z 厚い雲、w 稲光）。`toon.gdshaderinc` の `weather_wet`（吸う材ほど暗く深い色）・`weather_snow`（上を向いた面から白く）・
  `weather_puddle`（平らな道・広場の水たまりが空を映す）を地形・建物（瓦は濡れて艶）・草（先端に雪）・葉が使う。水面に雨の輪（`water.gdshader`）。
- ゲームへの影響（`HistWeather` の関数。値は控えめ）:
  火縄銃の不発 +35%×雨（小雨で約 +10%・雪 +12%・強風で口薬が飛ぶ +4%、屋内は 0）。自分の火縄銃も敵の火縄銃も。薬莢の小銃・弓は影響なし
  （根拠：火皿の口薬が湿ると点火が途切れる。火蓋・雨覆はその対策だが完全ではない＝国土交通省の多言語解説「火縄銃の仕組み」）。
  敵の気づく距離 ×見通し（濃霧 0.38・大雨 0.7・雪 0.7・夜 0.8、下限 0.35。任務の標的は従来どおり）。馬の速さ（土の道は濡れで −13%、雪で −16%）・車のグリップ（雪道 −40%）。
  船の揺れ（時化で縦揺れ ×3・横揺れ ×4、大きな船も揺れる）。飛行機の乱気流（Skills.plane_wobble に加算）。
  歴史の結果には影響させない（史実の天気が出来事を決めた因果は、歴史モデルの中に既にある分だけ。新しい規則は足していない）。
- HUD: 右上に天気の絵と「晴」「雨」「雪」「大雪」「雷雨」「台風」「霧」「降灰」「梅雨・雨」・地点・気温・風・出典の種類（史実の記録／後世の記録／記録（論争あり）／気候値／気候値＋代理指標）・
  日付（明治 6 年より前は旧暦も）。有名な日に降り立つと「史実：この日は大雪だった（桜田門外の変）」のような一言。
- 検査: `godot --headless --path . res://tests/test_weather.tscn`（旧暦の換算 20 例と往復・有名な日の上書き・上書きしない日・全時点の天気・気候値の妥当さ・
  不発/見通し/ぬかるみ・足音の言いかえと素材・WeatherDirector/HUD/環境音/Session がヘッドレスで動く）。
  写真: `xvfb-run -a godot --path . --rendering-driver vulkan --resolution 1280x720 res://tests/shot_weather.tscn -- edo:1860 sengoku:1600 kamakura_muromachi:1281 showa:1936:rain`。
- 素材: `tools/audio/gen_weather.py`（合成・CC0）。`python3 tools/audio/build.py --kenney <dir> --only "amb_rain_*,thunder_*,wind_gust,step_wet*,amb_storm_wind,amb_snow_hush"`。
- 調べられなかったこと: 気象庁の過去の気象データ（www.data.jma.go.jp）・山梨大学の歴史天候データベース（hwdb.yamanashi.ac.jp）・国立天文台の暦（eco.mtk.nao.ac.jp）は
  この作業環境から接続できなかった。明治以後の日ごとの観測値・江戸の日記の日ごとの天気は取り込めておらず、有名な日と月別の平年値のみ。
