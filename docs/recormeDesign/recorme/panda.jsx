// recorme mascot — the smiling red-panda image, gently swaying/bouncing in place.
function RedPanda() {
  return (
    <div style={{ position: "relative", width: 224, height: 196, display: "flex", alignItems: "flex-end", justifyContent: "center" }}>
      <div className="rc-mshadow" style={{ position: "absolute", bottom: 12, width: 130, height: 20, borderRadius: "50%",
        background: "radial-gradient(circle, rgba(80,50,20,.22), transparent 70%)", filter: "blur(2px)" }} />
      <img className="rc-mascot" src="recorme/mascot.png" alt="recorme 마스코트"
        style={{ width: 214, height: "auto", display: "block" }} />
    </div>
  );
}

window.RcPanda = RedPanda;
