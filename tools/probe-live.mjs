const ws = new WebSocket("ws://127.0.0.1:8791/ws");
const t0 = Date.now();
ws.addEventListener("open", () => ws.send(JSON.stringify({type:"hello", campaign:"live-probe", player:"GHOST"})));
ws.addEventListener("message", (ev) => {
  const m = JSON.parse(ev.data);
  if (m.type === "ready") {
    console.log("ready", m.model, m.pi.version, "mode", m.mode);
    ws.send(JSON.stringify({type:"ask", id:"p1", task:"dialogue", stream:true,
      input:{state:{player:{handle:"GHOST",day:1,credits:900,rep:8,heat:0}, contract:{codename:"探针",pay:1000,advance:0,risk:"中"}, chronicle:[], crew:[]}, message:"用一句话说明你是谁。"},
      actor:{kind:"fixer", id:"fixer", persona:{id:"fixer",name:"蜃楼"}}}));
  } else if (m.type === "delta") process.stdout.write(m.text);
  else if (m.type === "done" || m.type === "error") {
    console.log("\n---", m.type, "ok=", m.ok, "ms=", Date.now()-t0, "degraded=", m.degraded, "markers=", JSON.stringify(m.markers));
    ws.send(JSON.stringify({type:"reset"}));
    setTimeout(()=>process.exit(m.type === "done" ? 0 : 1), 400);
  }
});
setTimeout(()=>{ console.log("timeout"); process.exit(2); }, 60000);
