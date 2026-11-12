// Offline/degraded-mode narrative engine. Keeps the full loop playable when
// the local Pi agent or the model endpoint is unavailable.

const pick = (arr, seed) => arr[Math.abs(seed) % arr.length];

const CONTRACTS = [
  {
    codename: "静水回廊",
    client: "匿名雇主，由蜃楼转述；对方只留下一串被酸雨泡花的义体诊所会员卡号",
    target: "回澜义体诊所三楼的离线备份服务器",
    objective: "潜入诊所三楼机房，拷出离线服务器镜像，并抹掉当夜的访问日志",
    location: "澜港·旧城区第七层「回澜义体诊所」",
    pay: 1400,
    advance: 300,
    risk: "中",
    heat: 1,
    tags: ["潜入", "数据", "义体"],
    brief:
      "酸雨把招牌泡成一团绿雾。诊所凌晨三点换班，走廊里只剩消毒水和冷却液的味道。三楼机房不上网——这是难点，你得亲自进去，或者找个能进去的人。别碰前台的病人登记簿，雇主只说要那台服务器。",
    hook: "离线的东西才值钱，因为它们从没被备份过第二次。",
    twist: "那台服务器里除了委托数据，还存着雇主本人的全套手术与欠款记录——他是这家诊所的逃单病人，这单活是他用来删掉自己档案的。",
    approach_hint: "从消防梯上二层，避开前台与值班护士。",
  },
  {
    codename: "香槟协议",
    client: "赤潮中层「蝰蛇」，借蜃楼递话，语气客气得反常",
    target: "数据掮客「白鹭」袖扣里的存储芯片",
    objective: "在穹顶慈善拍卖会上接近白鹭，让他自愿把芯片交出来",
    location: "澜港·上层环带「云脊塔」第 88 层宴会厅",
    pay: 2800,
    advance: 600,
    risk: "中",
    heat: 1,
    tags: ["社交", "伪装", "拍卖会"],
    brief:
      "云脊塔第 88 层不下雨，只有循环风和调过信息素的空气。白鹭喝到第三杯就会去露台抽烟，那是你唯一的机会。入场要一份能过面部扫描的邀请函，和一张不会在闲聊里露怯的嘴。你有四十分钟。",
    hook: "不能抢，也不能偷——要让他觉得自己很聪明地把它送了出去。",
    twist: "白鹭早知道有人盯上芯片，他在替沧溟协议钓人；露台上三名便衣，你拿到手的那张邀请函就是诱饵编号。",
    approach_hint: "伪造服务商身份，从后勤通道进入宴会厅。",
  },
  {
    codename: "冷媒挽歌",
    client: "旧城区居民互助会众筹，蜃楼这次不收抽成",
    target: "赤潮「灰槽合成厂」的冷却循环系统",
    objective: "往冷却系统里埋一段延时过压指令，让整条产线自毁且不起火",
    location: "澜港·旧城区第十二层「赤潮·灰槽合成厂」",
    pay: 3600,
    advance: 0,
    risk: "高",
    heat: 2,
    tags: ["破坏", "工业", "赤潮"],
    brief:
      "灰槽厂昼夜不停，排气管在雨里吐白汽，像一道活着的伤口。拦不住你的不是防火墙，难的是不让人发现。让压力慢慢爬，爬到交接班那一刻才炸，谁都说不清是谁的错。别让它起火，楼下住着三百户人家。",
    hook: "毁掉一座工厂最干净的方式，是让它自己弄死自己。",
    twist: "这厂其实是穹顶生物科技废弃的中试车间，赤潮只是租客；一旦出事，穹顶会顺势把整层判为污染区清空——连楼下那三百户一起。",
    approach_hint: "先在外部配电井接入维护网，再让队友进入厂区。",
  },
];

const CREW = [
  {
    name: "铁娘子",
    handle: "IRONMAIDEN",
    role: "重装",
    origin: "前穹顶生物科技安保主管，工号被抹掉",
    look: "四十岁，左臂是一截旧式工业义体，指节上全是焊疤",
    voice: "短句，像在报数据；生气时反而更轻",
    personality: "冷硬、护短。讨厌空头承诺，但对守规矩的雇主有奇特的忠诚",
    quirk: "谈正事前会先确认出口位置",
    like: "提前给到的建筑图",
    dislike: "“事后补一句”的承诺",
    price: 380,
    loyalty: 55,
    skills: { intrusion: 2, ew: 2, analysis: 2, stealth: 3, tech: 3, social: 2, combat: 5, nerve: 4 },
    perk: "重火力的同时懂得拆掉整层楼的电闸",
    secret: "她一直在查当年那场让七名下属送命的“演习”，而命令的签发人还活着。",
    pitch: "要进有人的地方，找我。我负责让人不敢拦你。",
  },
  {
    name: "针",
    handle: "NEEDLE",
    role: "潜入",
    origin: "旧城马戏团出身，后来替赤潮做“高空取物”",
    look: "瘦，关节像没有骨头，指腹全是消掉的纹路",
    voice: "轻快，爱开玩笑，紧张时话更多",
    personality: "轻浮、好奇、手不干净；跑路前会回头确认同伴都在",
    quirk: "从不走正门，哪怕正门开着",
    like: "复杂得像谜题的排风管",
    dislike: "被要求站着不动",
    price: 300,
    loyalty: 48,
    skills: { intrusion: 2, ew: 1, analysis: 2, stealth: 5, tech: 3, social: 3, combat: 2, nerve: 2 },
    perk: "在没有路的地方找出一条路",
    secret: "她上个月从赤潮的账房里顺走了一枚筹码，现在有人在找它。",
    pitch: "门锁是给人用的。我只用窗、管道和别人的疏忽。",
  },
  {
    name: "老猫",
    handle: "OLDCAT",
    role: "技术",
    origin: "夜航早期的硬件商，卖过假货也救过人命",
    look: "六十上下，义眼一只是二手货，颜色对不上",
    voice: "絮叨，喜欢把每件事拆成三个风险",
    personality: "多疑、谨慎、嘴碎；对机器比对人有耐心",
    quirk: "随身带一块焊坏的旧主板，说是护身符",
    like: "别人不要的旧设备",
    dislike: "现场临时改方案",
    price: 260,
    loyalty: 60,
    skills: { intrusion: 4, ew: 4, analysis: 4, stealth: 2, tech: 5, social: 2, combat: 1, nerve: 3 },
    perk: "能在一堆报废设备里拼出能用的东西",
    secret: "他的义眼其实还在向某个旧主顾回传画面，他不敢拆。",
    pitch: "你们打打杀杀，我拆锁、断电、让摄像头集体失明。",
  },
  {
    name: "白噪",
    handle: "WHITENOISE",
    role: "交涉",
    origin: "云脊塔前公关，替三家财团处理过不该上新闻的事",
    look: "永远熨得平整的西装，笑容像调过参数",
    voice: "温和，礼貌，带一点居高临下的耐心",
    personality: "优雅、算计、享受操控；不轻易欠人情",
    quirk: "说话时习惯替对方补完句子",
    like: "有筹码的谈判",
    dislike: "暴力，认为那是没脑子的人用的工具",
    price: 520,
    loyalty: 42,
    skills: { intrusion: 2, ew: 2, analysis: 3, stealth: 2, tech: 2, social: 5, combat: 1, nerve: 4 },
    perk: "一张能进大多数场合的脸和一套现编的履历",
    secret: "他替穹顶处理过的一份名单里，有玩家正在找的人。",
    pitch: "大部分门不需要撬开，只需要有人相信门本来就该为你打开。",
  },
  {
    name: "柴油",
    handle: "DIESEL",
    role: "撤离",
    origin: "旧城运输队的司机，欠了赤潮一笔修车钱",
    look: "壮，脖子后面纹着一条被雨泡褪色的鱼",
    voice: "慢，热络，喜欢用食物打比方",
    personality: "讲义气、怕麻烦、关键时刻不含糊",
    quirk: "不管多急都要先把车预热三次",
    like: "加满油的车和热汤",
    dislike: "临时加人、临时改路线",
    price: 240,
    loyalty: 58,
    skills: { intrusion: 1, ew: 1, analysis: 2, stealth: 3, tech: 4, social: 3, combat: 3, nerve: 4 },
    perk: "闭着眼也能把车开进旧城任何一条巷子",
    secret: "他那笔修车钱其实是替妹妹还的，妹妹在穹顶的试验名单上。",
    pitch: "你负责搞定上面，我负责让轮子一直转。",
  },
  {
    name: "无面",
    handle: "FACELESS",
    role: "重装",
    origin: "不知道。他自己说以前「在远处看人」",
    look: "高，瘦，脸上有半张义体面甲，从不摘",
    voice: "极少说话，一次不超过十个字",
    personality: "沉默、精准、不解释；对噪音异常敏感",
    quirk: "接下活以后会把整条撤离路线在纸上画一遍",
    like: "安静的高处",
    dislike: "临场发挥",
    price: 460,
    loyalty: 45,
    skills: { intrusion: 2, ew: 2, analysis: 4, stealth: 5, tech: 2, social: 1, combat: 4, nerve: 5 },
    perk: "隔着两条街替你把麻烦解决在视线之外",
    secret: "他的面甲下面，是玩家上一个雇主留下的标记。",
    pitch: "给我一个位置。其他的不用管。",
  },
];

const STAGES = ["接近", "渗透", "目标", "撤离"];

function crewOrPlayer(input, index = 0) {
  const crew = input?.state?.crew || [];
  return crew.length ? crew[index % crew.length] : null;
}

function stageBeat(stageIndex, input) {
  const c = input.state?.contract || {};
  const crew = input.state?.crew || [];
  const c0 = crew[0];
  const c1 = crew[1] || crew[0];
  const place = c.location || "现场";
  const target = c.target || "目标";
  const situations = [
    `雨在${place}外沿的铁皮上敲出密集的响。${c0 ? `${c0.name}已经到位，蹲在阴影里等你的口令` : "你只有屏幕上的建筑图和一颗不太稳的心"}。入口有两处：正门亮着，侧门有读卡器，外墙的维护梯通向二层平台。${target}在建筑深处，静静地等着。`,
    `${c0 ? `${c0.name}贴着墙移动` : "你远程接管了第一道门锁"}，指示灯从红转绿只花了一秒。里面比外面更安静，安静得像有人在屏住呼吸。走廊尽头的摄像头缓慢转头，暂时还没看到这里。信号里混进了不该有的电流杂音。`,
    `目标就在前方。${target}的外壳在应急灯下泛着冷光，接线口有一段被反复插拔的划痕。${c0 ? `${c0.name}在耳机里问：“现在？”` : "你的手指停在回车键上"}。时间不多，任何多余的动作都会留下记录。`,
    `撤离通道在身后合拢。雨重新落进画面里，${c0 ? `${c0.name}的呼吸` : "你的终端风扇"}是唯一稳定的声音。楼里的灯一层层亮起来，有人已经发现不对，但还没找到方向。`,
  ];
  const actionsByStage = [
    [
      { label: `让${c0 ? c0.name : "你"}从维护梯上二层`, skill: "stealth", actor: c0?.id || "player", risk: "低" },
      { label: `远程接管侧门读卡器`, skill: "intrusion", actor: "player", risk: "中" },
      { label: `让${c1 ? c1.name : "你"}在前门制造动静`, skill: "combat", actor: c1?.id || "player", risk: "高" },
    ],
    [
      { label: `让${c0 ? c0.name : "你"}贴墙绕过摄像头`, skill: "stealth", actor: c0?.id || "player", risk: "中" },
      { label: `远程循环走廊监控画面`, skill: "ew", actor: "player", risk: "低" },
      { label: `让${c1 ? c1.name : "你"}断开这段的照明`, skill: "tech", actor: c1?.id || "player", risk: "中" },
    ],
    [
      { label: `让${c0 ? c0.name : "你"}接入目标接口`, skill: "tech", actor: c0?.id || "player", risk: "中" },
      { label: `远程绕过目标的锁死协议`, skill: "intrusion", actor: "player", risk: "高" },
      { label: `让${c1 ? c1.name : "你"}盯住走廊尽头`, skill: "nerve", actor: c1?.id || "player", risk: "低" },
    ],
    [
      { label: `让${c0 ? c0.name : "你"}按原路撤回`, skill: "stealth", actor: c0?.id || "player", risk: "中" },
      { label: `远程伪造一次火警分散注意`, skill: "ew", actor: "player", risk: "中" },
      { label: `让${c1 ? c1.name : "你"}守住撤离通道`, skill: "combat", actor: c1?.id || "player", risk: "高" },
    ],
  ];
  return {
    name: STAGES[stageIndex],
    situation: situations[stageIndex],
    pressure:
      stageIndex === 0
        ? "换班还有十分钟。"
        : stageIndex === 1
          ? "监控轮巡大约每四十秒一次。"
          : stageIndex === 2
            ? "目标只露出不到两分钟的操作窗口。"
            : "警报随时可能被拉响。",
    actions: actionsByStage[stageIndex],
    support_ops: [
      {
        label: stageIndex === 0 ? "扫描楼宇网络找入口" : "伪造一段合法门禁记录",
        skill: stageIndex === 0 ? "analysis" : "intrusion",
        cost: 1,
        hint: "可能降低下一拍的难度",
      },
      {
        label: "压制现场通讯频段",
        skill: "ew",
        cost: 1,
        hint: "减少警报扩散",
      },
    ],
  };
}

export function mockTask(task, input = {}, ctx = {}) {
  const state = input.state || {};
  const crew = state.crew || [];
  const contract = state.contract || {};
  switch (task) {
    case "contracts": {
      const day = state.player?.day ?? 1;
      const count = input.count || 3;
      const list = [];
      for (let i = 0; i < count; i++) {
        const base = CONTRACTS[(day + i) % CONTRACTS.length];
        list.push({ ...base, pay: Math.round(base.pay * (0.9 + ((day + i) % 3) * 0.08)) });
      }
      return { data: { contracts: list }, degraded: true };
    }
    case "crew": {
      const count = input.count || 3;
      const start = (state.player?.day ?? 1) % CREW.length;
      const list = [];
      for (let i = 0; i < count; i++) list.push({ ...CREW[(start + i) % CREW.length] });
      return { data: { crew: list }, degraded: true };
    }
    case "run_start": {
      const beat = stageBeat(0, input);
      const c = contract;
      const c0 = crewOrPlayer(input, 0);
      const narration = `雨把${c.location || "现场"}外的霓虹揉成一团模糊的光。你的工作台上并排开着三个窗口：建筑结构、通讯链路，还有 ${c0 ? c0.name : "你"} 的生命体征。${c0 ? `${c0.name}的声音从耳机里传出来，压得很低：“到了。你说怎么进。”` : "没有队友，只有你和屏幕里那扇门。"} 这是「${c.codename || "行动"}」的第一步，任何多余的动作都会留在城市的记忆里。`;
      return { narration, data: { beat, secret_hint: null }, degraded: true };
    }
    case "run_beat": {
      const tier = input.tier || "成功";
      const stageIndex = Math.min(3, input.beatIndex ?? 0);
      const c0 = crewOrPlayer(input, 0);
      const name = c0?.name || "你";
      const lines = {
        大成功: `${name}的动作干净得不像真的。${stageIndex === 2 ? "目标在没有任何警报的情况下被打开，里面的东西安静地流进你的终端。" : "不但按计划完成，还顺手拿到了一个不该拿的东西——一段加密记录，或者一个还亮着的权限。"}雨声盖住了一切。`,
        成功: `${name}按计划推进。${stageIndex === 2 ? "接口接上，数据开始流动，进度条在屏幕角落稳定地爬。" : "没有多余的声音，没有多余的停顿。耳机里只传来一声很轻的确认。"}现场仍然安全，但时间又少了一点。`,
        勉强: `${name}完成了动作，但代价来得比预想快。${stageIndex === 2 ? "目标开了，可是一条旁路日志被写了进去。" : "远处传来一声金属摩擦，像有什么被碰倒了。"}耳机里安静了两秒，然后是压低的一句：“有点麻烦。”`,
        失败: `事情没有按计划走。${stageIndex === 2 ? "接口在最后一刻锁死，目标进入保护状态。" : "灯光、脚步或者一道不该出现的扫描，把计划撕开了一个口子。"}${name}退回阴影里，呼吸变重。你必须在下一波反应到来前重新决定。`,
      };
      const next = stageIndex < 3 ? stageBeat(stageIndex + 1, input) : null;
      const effects = [];
      if (tier === "失败") effects.push({ type: "heat", delta: 1 });
      if (tier === "勉强") effects.push({ type: "heat", delta: 1 });
      if (tier === "大成功" && stageIndex === 2) effects.push({ type: "credits", delta: 120 });
      return {
        narration: lines[tier] || lines["成功"],
        data: {
          effects,
          next,
          reveal: tier === "大成功" ? "你截到一段不属于本次委托的通讯碎片。" : null,
          crew_line: c0 ? (tier === "失败" ? "“我还在。但别再来一次了。”" : "“干净。”") : null,
          alarm: 0,
        },
        degraded: true,
      };
    }
    case "settle": {
      const r = input.results || {};
      const c = contract;
      const c0 = crewOrPlayer(input, 0);
      const narration = `撤出来的路上，雨忽然小了。${c.location || "现场"}的灯还亮着，像什么都没发生过。你的终端里多了一笔干净的信用点，少了一段可以回头的路。${c0 ? `${c0.name}在通讯里沉默了一会儿，说：“下次先说清楚会有几个人。”` : "没有人给你发消息。安全屋里只有风扇的声音。"} 蜃楼最后只回了一行字：“钱到了。别急着接下一单。”`;
      return {
        narration,
        data: {
          loot: r.successes >= 3 ? [{ name: "加密记录碎片", desc: "一段没有署名的高层通讯，也许以后能换钱。", value: 220 }] : [],
          hook: "旧城区有人在打听这次行动的细节，出价不低。",
          world_change: `${c.target || "目标"}的安保在事后换了一批人，有人开始追查那条被用过一次的后门。`,
          crew_lines: c0 ? [{ id: c0.id, line: "钱按说好的分。下次别把撤退路线写在同一个地方。" }] : [],
          secrets: [],
          fixer_line: "干得不算漂亮，但干完了。蜃楼这边还有活。",
        },
        degraded: true,
      };
    }
    case "plan_audit": {
      const plan = input.plan || {};
      const notes = [];
      if (!plan.crew || plan.crew.length === 0) notes.push("没有现场队友，失败时没人替你收场。");
      if (plan.approach === "强攻") notes.push("强攻会在头两拍就把热度推上去。");
      if (plan.entry === "正门") notes.push("正门有两次身份核验，伪造件撑不住。");
      notes.push("留一条不依赖城市电网的撤离路线。");
      return {
        data: { verdict: notes.length > 2 ? "危险" : "勉强", risk_score: Math.min(95, 35 + notes.length * 12), notes: notes.slice(0, 4), line: "能打，但别把运气算进计划。" },
        degraded: true,
      };
    }
    case "event": {
      const events = [
        { title: "潮湿的传票", text: "沧溟协议的巡逻无人机在你所在楼层多绕了一圈。没有人敲门，但门口多了一枚被雨泡皱的市政通知，上面印着你的旧地址。", severity: "中", effects: [], hook: "有人在确认你还住在这里。" },
        { title: "夜航的敲门声", text: "一个匿名节点给你发来半张地图，标注着穹顶在中层新设的数据井。附言只有一句：“欠你一次。”", severity: "低", effects: [], hook: "数据井的守备图也许值钱。" },
        { title: "旧债", text: "赤潮的人在旧城区打听一个只闻其声的黑客。他们没找到你，但找到了一个曾经替你跑腿的人。", severity: "高", effects: [{ type: "heat", delta: 1 }], hook: "有人替你挨了一顿打。" },
      ];
      return { data: pick(events, (state.player?.day ?? 1) + 1), degraded: true };
    }
    case "recruit": {
      const c = input.crew || {};
      const offer = input.offer || {};
      const cut = offer.cut ?? c.price ?? 300;
      const accept = cut >= (c.price ?? 300) * 0.9 || (c.loyalty ?? 50) >= 65;
      return {
        text: accept
          ? `行。${input.state?.contract?.codename ? `「${input.state.contract.codename}」这单我接了。` : "这单我接。"}钱按你说的分，别临时改路线。`
          : `这点钱不够我把命押进去。${Math.round((c.price ?? 300) * 1.15)}，少一个子儿都免谈。`,
        markers: accept ? { deals: [{ cut }], accepted: true } : { deals: [], accepted: false, refused: "报酬不足" },
        degraded: true,
      };
    }
    case "dialogue": {
      const actor = input.actor || {};
      const msg = String(input.message || "");
      if (input.actorKind === "fixer") {
        const replies = [
          "钱在账上，话就别太多。你要接就接，不接我把活给别人。",
          "别跟我谈感情。谈风险，谈你能拿什么换。",
          "这单的雇主比你还怕见光。你只要把东西带出来，剩下的我来擦。",
        ];
        const text = pick(replies, msg.length);
        return { text, markers: (msg.includes("价") || msg.includes("钱") || msg.includes("报酬") || msg.includes("加")) ? { deals: [{ pay: 100, advance: 50 }] } : {}, degraded: true };
      }
      const name = actor.name || "佣兵";
      const personality = actor.personality || "沉默";
      if (/钱|价|报酬|分成/.test(msg)) {
        return { text: `钱的事先说清楚。${actor.price ?? 300}，这是看在你以前没坑过人的份上。任务里要是加东西，得另算。`, markers: {}, degraded: true };
      }
      if (/任务|活|委托|目标/.test(msg)) {
        return { text: `我看了你发来的东西。能做，但别指望一点动静都没有。${personality.includes("多疑") ? "先把撤离路线定死，我不喜欢临场发挥。" : "你负责上面，我负责脚下。"}`, markers: {}, degraded: true };
      }
      return { text: `「${name}」在通讯那头停了一下，背景里有雨和机器的声音。“说吧。我听着。”`, markers: {}, degraded: true };
    }
    default:
      return { text: "", data: null, degraded: true };
  }
}

