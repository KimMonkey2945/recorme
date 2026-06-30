const { Icon, IconButton, Avatar, Button, Logo, Divider, Tag } = window.WantedDesignSystem_f8da76;

/* ── date helpers ─────────────────────────────────────────── */
const WEEK_KO = ["일", "월", "화", "수", "목", "금", "토"];
function parseDate(s) { const [y, m, d] = s.split("-").map(Number); return new Date(y, m - 1, d); }
function pad(n) { return String(n).padStart(2, "0"); }
function toKey(dt) { return `${dt.getFullYear()}-${pad(dt.getMonth() + 1)}-${pad(dt.getDate())}`; }
function fmtLong(s) { const d = parseDate(s); return `${d.getMonth() + 1}월 ${d.getDate()}일 ${WEEK_KO[d.getDay()]}요일`; }
function fmtListHeader(s) { const d = parseDate(s); return { day: d.getDate(), md: `${d.getMonth() + 1}월`, wk: WEEK_KO[d.getDay()] }; }
window.RC = { WEEK_KO, parseDate, pad, toKey, fmtLong, fmtListHeader };

/* ── AppBar ──────────────────────────────────────────────── */
function AppBar({ title, onBack, onProfile, onLogout, sticky = true, big }) {
  return (
    <div style={{
      minHeight: 56, display: "flex", alignItems: "center", gap: 4, padding: "0 6px 0 10px",
      borderBottom: "1px solid var(--line-alternative)", background: "var(--bg-normal)",
      position: sticky ? "sticky" : "static", top: 0, zIndex: 8,
    }}>
      {onBack
        ? <IconButton styleType="normal" onClick={onBack}><Icon name="chevronLeft" size={24} /></IconButton>
        : <span style={{ marginLeft: 6, display: "flex" }}><Logo type="wordmark" height={18} color="var(--label-strong)" /></span>}
      <div style={{ flex: 1, textAlign: onBack ? "center" : "left", paddingLeft: onBack ? 0 : 6,
        font: "700 17px var(--font-sans)", color: "var(--text-strong)", letterSpacing: "-0.02em" }}>{title}</div>
      <div style={{ display: "flex", alignItems: "center" }}>
        {onProfile && (
          <button onClick={onProfile} style={{ border: 0, background: "none", cursor: "pointer", padding: 4 }}>
            <Avatar name={window.RECORME_USER.nickname} size="sm" />
          </button>
        )}
        {onLogout && <IconButton styleType="normal" onClick={onLogout}><Icon name="externalLink" size={22} /></IconButton>}
      </div>
    </div>
  );
}

/* ── Confirm dialog ──────────────────────────────────────── */
function ConfirmDialog({ open, title, body, confirmLabel = "확인", cancelLabel = "취소",
  tone = "primary", icon, onConfirm, onCancel }) {
  if (!open) return null;
  return (
    <div onClick={onCancel} style={{
      position: "absolute", inset: 0, zIndex: 40, background: "rgba(23,23,25,0.52)",
      display: "flex", alignItems: "center", justifyContent: "center", padding: 28,
      animation: "rcFade .15s ease",
    }}>
      <div onClick={(e) => e.stopPropagation()} style={{
        width: "100%", maxWidth: 320, background: "var(--bg-normal)", borderRadius: 20,
        padding: "26px 22px 18px", boxShadow: "0 20px 50px rgba(23,23,25,0.3)", textAlign: "center",
        animation: "rcPop .18s cubic-bezier(.2,.8,.3,1.2)",
      }}>
        {icon && (
          <div style={{ width: 48, height: 48, borderRadius: 24, margin: "0 auto 14px", display: "flex",
            alignItems: "center", justifyContent: "center",
            background: tone === "negative" ? "var(--negative-assistive,#FFECEC)" : "var(--primary-assistive,#EAF0FF)",
            color: tone === "negative" ? "var(--negative-normal)" : "var(--primary-normal)" }}>
            <Icon name={icon} size={26} />
          </div>
        )}
        <div style={{ font: "700 18px var(--font-sans)", color: "var(--text-strong)", letterSpacing: "-0.02em" }}>{title}</div>
        {body && <div style={{ font: "400 14px/1.55 var(--font-sans)", color: "var(--text-alternative)", marginTop: 8 }}>{body}</div>}
        <div style={{ display: "flex", gap: 8, marginTop: 22 }}>
          <Button variant="outlined" color="assistive" size="lg" fullWidth onClick={onCancel}>{cancelLabel}</Button>
          <Button variant="solid" color={tone === "negative" ? "negative" : "primary"} size="lg" fullWidth onClick={onConfirm}>{confirmLabel}</Button>
        </div>
      </div>
    </div>
  );
}

/* ── Toast ───────────────────────────────────────────────── */
function Toast({ toast }) {
  if (!toast) return null;
  const neg = toast.tone === "negative";
  return (
    <div style={{
      position: "absolute", left: 20, right: 20, bottom: 92, zIndex: 50,
      display: "flex", alignItems: "center", gap: 10, padding: "13px 16px", borderRadius: 12,
      background: neg ? "var(--negative-normal)" : "rgba(23,23,25,0.92)", color: "#fff",
      font: "500 14px var(--font-sans)", boxShadow: "0 10px 30px rgba(23,23,25,0.28)",
      animation: "rcToast .25s ease",
    }}>
      <Icon name={neg ? "circleExclamationFill" : "circleCheckFill"} size={20} />
      <span style={{ flex: 1 }}>{toast.msg}</span>
    </div>
  );
}

/* ── empty state ─────────────────────────────────────────── */
function Empty({ icon, title, sub }) {
  return (
    <div style={{ display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center",
      gap: 10, padding: "80px 32px", textAlign: "center", color: "var(--text-assistive)" }}>
      <div style={{ width: 64, height: 64, borderRadius: 32, background: "var(--bg-alternative,#F7F7F8)",
        display: "flex", alignItems: "center", justifyContent: "center", color: "var(--text-assistive)" }}>
        <Icon name={icon} size={30} />
      </div>
      <div style={{ font: "600 16px var(--font-sans)", color: "var(--text-neutral)" }}>{title}</div>
      {sub && <div style={{ font: "400 13px/1.5 var(--font-sans)" }}>{sub}</div>}
    </div>
  );
}

Object.assign(window, { RcAppBar: AppBar, RcConfirm: ConfirmDialog, RcToast: Toast, RcEmpty: Empty });
