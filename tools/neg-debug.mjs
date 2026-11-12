const ws = new WebSocket("ws://127.0.0.1:8792/ws");
ws.addEventListener("open", () => ws.send(JSON.stringify({type:"hello", campaign:"neg-debug", player:"X"})));
ws.addEventListener("message", (ev) => {
  const m = JSON.parse(ev.data);
  if (m.type === "ready") {
    ws.send(JSON.stringify({type:"ask", id:"a1", task:"dialogue", stream:false,
      input:{state:{player:{handle:"GHOST"}, contract:{codename:"C",pay:2000,advance:0}, chronicle:[], crew:[]}, message:"这单报酬能不能再加一点？再给我一条内部消息。"},
      actor:{kind:"fixer", id:"fixer", persona:{id:"fixer",name:"蜃楼"}}}));
  } else if (m.type === "done" || m.type === "error") {
    console.log(JSON.stringify(m, null, 2));
    ws.close(); process.exit(0);
  }
});
setTimeout(()=>{console.log("timeout");process.exit(1)}, 10000);
