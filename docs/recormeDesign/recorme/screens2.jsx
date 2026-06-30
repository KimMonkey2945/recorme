const { Icon, IconButton, Avatar, Button, Divider, Tag } = window.WantedDesignSystem_f8da76;
const { fmtLong, fmtListHeader, parseDate, WEEK_KO } = window.RC;
const MAX = 500;

/* ════ EDITOR (F003 / F006) ═════════════════════════════════ */
function Editor({ layout, date, initial, mode, onCancel, onRegister, onConfirm }) {
  const [text, setText] = React.useState(initial || "");
  const taRef = React.useRef(null);
  React.useEffect(() => { taRef.current && taRef.current.focus(); }, []);
  const len = text.length;
  const empty = text.trim().length === 0;

  const paper = layout === "paper";
  const focus = layout === "focus";

  const surface = paper
    ? { background: "var(--bg-paper,#FBF9F4)" }
    : { background: "var(--bg-normal)" };

  const inputWrap = layout === "clean"
    ? { margin: "16px 20px 0", border: "1px solid var(--line-alternative)", borderRadius: 16, padding: "16px 16px 8px",
        background: "var(--bg-normal)", boxShadow: "0 1px 3px rgba(23,23,25,.05)" }
    : { padding: focus ? "8px 26px 0" : "8px 22px 0" };

  const taStyle = {
    width: "100%", boxSizing: "border-box", border: 0, outline: "none", resize: "none", background: "transparent",
    minHeight: focus ? 320 : 240,
    font: paper ? "400 17px/2.0 var(--font-serif, Georgia, serif)" : `400 ${focus ? 18 : 16}px/1.85 var(--font-sans)`,
    color: "var(--text-normal)", letterSpacing: "-0.01em",
    ...(paper ? {
      backgroundImage: "repeating-linear-gradient(transparent, transparent 35px, var(--line-alternative) 35px, var(--line-alternative) 36px)",
      backgroundAttachment: "local", paddingTop: 8,
    } : {}),
  };

  return (
    <div style={{ display: "flex", flexDirection: "column", height: "100%", ...surface }}>
      {/* top bar */}
      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", padding: "0 8px 0 14px",
        minHeight: 56, borderBottom: layout === "clean" ? "1px solid var(--line-alternative)" : "none", ...surface,
        position: "sticky", top: 0, zIndex: 6 }}>
        <Button variant="text" color="assistive" size="md" onClick={onCancel}>취소</Button>
        <div style={{ font: "600 14px var(--font-sans)", color: "var(--text-neutral)" }}>{fmtLong(date)}</div>
        <span style={{ width: 52 }} />
      </div>

      {/* date headline (paper/focus) */}
      {layout !== "clean" && (
        <div style={{ padding: focus ? "18px 26px 0" : "16px 22px 0" }}>
          <div style={{ font: "700 24px var(--font-sans)", color: "var(--text-strong)", letterSpacing: "-0.02em" }}>
            {parseDate(date).getDate()}일 <span style={{ color: "var(--text-alternative)", fontWeight: 500, fontSize: 16 }}>{WEEK_KO[parseDate(date).getDay()]}요일</span>
          </div>
          {mode === "edit" && <Tag color="neutral" style={{ marginTop: 8 }}>임시저장 이어쓰기</Tag>}
        </div>
      )}

      {/* input */}
      <div style={{ flex: 1, overflowY: "auto" }}>
        <div style={inputWrap}>
          <textarea ref={taRef} value={text} maxLength={MAX} onChange={(e) => setText(e.target.value)}
            placeholder={"오늘은 어떤 하루였나요?\n떠오르는 대로 편하게 적어보세요."} style={taStyle} />
          {/* photos (F012) */}
          {!focus && (
            <div style={{ display: "flex", gap: 8, padding: "12px 0 16px", flexWrap: "wrap" }}>
              <image-slot id="rc-photo-1" shape="rounded" radius="12" placeholder="사진"
                style={{ width: 72, height: 72, display: "block", boxShadow: "inset 0 0 0 1px var(--line-alternative)" }}></image-slot>
              <image-slot id="rc-photo-2" shape="rounded" radius="12" placeholder="사진"
                style={{ width: 72, height: 72, display: "block", boxShadow: "inset 0 0 0 1px var(--line-alternative)" }}></image-slot>
              <div style={{ width: 72, height: 72, borderRadius: 12, border: "1px dashed var(--line-normal,#cfd2d8)",
                display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", gap: 2,
                color: "var(--text-assistive)", font: "500 11px var(--font-sans)" }}>
                <Icon name="plus" size={18} /><span>0/5</span>
              </div>
            </div>
          )}
        </div>
      </div>

      {/* footer */}
      <div style={{ padding: "10px 16px calc(10px + env(safe-area-inset-bottom))", borderTop: "1px solid var(--line-alternative)",
        ...surface }}>
        <div style={{ display: "flex", justifyContent: "flex-end", font: "400 12px var(--font-sans)",
          color: len >= MAX ? "var(--negative-normal)" : "var(--text-assistive)", marginBottom: 8 }}>{len} / {MAX}</div>
        <div style={{ display: "flex", gap: 8 }}>
          <Button variant="outlined" color="assistive" size="lg" onClick={() => onRegister(text)} disabled={empty}
            style={{ flex: 1 }}>등록</Button>
          <Button variant="solid" color="primary" size="lg" onClick={() => onConfirm(text)} disabled={empty}
            leadingIcon={<Icon name="sparkle" size={18} />} style={{ flex: 1.4 }}>오늘을 기억하기</Button>
        </div>
      </div>
    </div>
  );
}

/* ════ DETAIL (F005 / F007) ═════════════════════════════════ */
function Detail({ diary, onBack, onEdit, onDelete }) {
  const d = diary;
  const dt = parseDate(d.date);
  const isDraft = d.status === "DRAFT";
  return (
    <div style={{ display: "flex", flexDirection: "column", height: "100%", background: "var(--bg-paper,#FBF9F4)" }}>
      <window.RcAppBar onBack={onBack} title="" />
      <div style={{ flex: 1, overflowY: "auto", padding: "8px 24px 24px" }}>
        <div style={{ font: "500 14px var(--font-sans)", color: "var(--text-alternative)" }}>
          {dt.getFullYear()}년 {dt.getMonth() + 1}월
        </div>
        <div style={{ font: "800 36px var(--font-display)", color: "var(--rc-ink, var(--text-strong))", letterSpacing: "-0.01em", marginTop: 2 }}>
          {dt.getDate()}일 <span style={{ fontSize: 20, fontWeight: 600, color: "var(--text-alternative)", fontFamily: "var(--font-sans)" }}>{WEEK_KO[dt.getDay()]}요일</span>
        </div>

        {/* status */}
        {isDraft ? (
          <div style={{ marginTop: 16, display: "flex", alignItems: "center", gap: 8, padding: "12px 14px", borderRadius: 12,
            background: "var(--bg-alternative,#EFF0F2)", color: "var(--text-neutral)", font: "500 13px var(--font-sans)" }}>
            <Icon name="pencil" size={18} /><span>임시 저장된 기록이에요. 이어서 쓰거나 오늘을 기억할 수 있어요.</span>
          </div>
        ) : (
          <div style={{ marginTop: 16, display: "flex", alignItems: "center", gap: 10, padding: "12px 14px", borderRadius: 12,
            background: "var(--accent-violet-assistive,#F0ECFE)", color: "var(--accent-violet,#6541F2)" }}>
            <span className="rc-spin" style={{ display: "flex" }}><Icon name="sparkle" size={18} /></span>
            <div style={{ font: "500 13px/1.4 var(--font-sans)" }}>
              <div style={{ fontWeight: 700 }}>감정을 분석하고 있어요</div>
              <div style={{ color: "var(--text-alternative)", marginTop: 1 }}>곧 이 날의 감정이 기록에 담길 거예요.</div>
            </div>
          </div>
        )}

        {/* content */}
        <div style={{ marginTop: 22, font: "400 17px/2.0 var(--font-serif, Georgia, serif)", color: "var(--text-normal)",
          whiteSpace: "pre-wrap", letterSpacing: "-0.01em" }}>{d.content}</div>

        {d.photos && d.photos.length > 0 && (
          <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 8, marginTop: 20 }}>
            {d.photos.map((p, i) => <div key={i} style={{ aspectRatio: "1", borderRadius: 12, background: "var(--bg-alternative)" }} />)}
          </div>
        )}
      </div>

      {/* footer */}
      <div style={{ display: "flex", gap: 8, padding: "12px 16px calc(12px + env(safe-area-inset-bottom))",
        borderTop: "1px solid var(--line-alternative)", background: "var(--bg-normal)" }}>
        <IconButton styleType="outlined" size="lg" color="default" onClick={onDelete}>
          <Icon name="trash" size={22} />
        </IconButton>
        {isDraft
          ? <Button variant="solid" color="primary" size="lg" fullWidth leadingIcon={<Icon name="pencil" size={18} />} onClick={onEdit}>이어 쓰기</Button>
          : <Button variant="outlined" color="assistive" size="lg" fullWidth onClick={onBack}>닫기</Button>}
      </div>
    </div>
  );
}

/* ════ LIST (F004) ══════════════════════════════════════════ */
function List({ layout, diaries, onOpen, onProfile, onLogout }) {
  const sorted = [...diaries].sort((a, b) => a.date < b.date ? 1 : -1);
  return (
    <div style={{ paddingBottom: 24 }}>
      <window.RcAppBar title="기록" onProfile={onProfile} onLogout={onLogout} />
      <div style={{ padding: "18px 20px 4px" }}>
        <div style={{ font: "700 26px var(--font-display)", color: "var(--rc-ink, var(--text-strong))", letterSpacing: "-0.01em" }}>지나온 날들</div>
        <div style={{ font: "500 13px var(--font-sans)", color: "var(--text-assistive)", marginTop: 2 }}>총 {sorted.length}개의 기록</div>
      </div>
      {sorted.length === 0
        ? <window.RcEmpty icon="document" title="아직 기록이 없어요" sub="캘린더에서 오늘을 기록해보세요." />
        : <div style={{ padding: "12px 20px 0" }}>{
            layout === "cards" ? <ListCards items={sorted} onOpen={onOpen} />
            : layout === "compact" ? <ListCompact items={sorted} onOpen={onOpen} />
            : <ListTimeline items={sorted} onOpen={onOpen} />
          }</div>}
    </div>
  );
}

function preview(c) { return c.replace(/\n+/g, " "); }

function ListTimeline({ items, onOpen }) {
  return (
    <div style={{ position: "relative" }}>
      <div style={{ position: "absolute", left: 23, top: 8, bottom: 8, width: 2, background: "var(--line-alternative)" }} />
      <div style={{ display: "flex", flexDirection: "column", gap: 4 }}>
        {items.map(d => {
          const h = fmtListHeader(d.date);
          return (
            <button key={d.id} onClick={() => onOpen(d.id)} style={{ display: "flex", gap: 14, padding: "10px 0", border: 0,
              background: "none", cursor: "pointer", textAlign: "left", width: "100%", alignItems: "flex-start" }}>
              <div style={{ flexShrink: 0, width: 48, textAlign: "center", zIndex: 1 }}>
                <div style={{ width: 48, height: 48, borderRadius: 24, background: "var(--bg-normal)",
                  boxShadow: "inset 0 0 0 1px var(--line-alternative)", display: "flex", flexDirection: "column",
                  alignItems: "center", justifyContent: "center" }}>
                  <div style={{ font: "700 16px var(--font-sans)", color: "var(--text-strong)", lineHeight: 1 }}>{h.day}</div>
                  <div style={{ font: "500 10px var(--font-sans)", color: "var(--text-assistive)", marginTop: 2 }}>{h.wk}</div>
                </div>
              </div>
              <div style={{ flex: 1, minWidth: 0, paddingTop: 4 }}>
                <div style={{ display: "flex", alignItems: "center", gap: 6 }}>
                  <span style={{ font: "600 13px var(--font-sans)", color: "var(--text-alternative)" }}>{h.md}</span>
                  {d.status === "DRAFT" && <Tag color="neutral">임시</Tag>}
                </div>
                <div style={{ font: "400 14px/1.55 var(--font-sans)", color: "var(--text-neutral)", marginTop: 4,
                  display: "-webkit-box", WebkitLineClamp: 2, WebkitBoxOrient: "vertical", overflow: "hidden" }}>{preview(d.content)}</div>
              </div>
            </button>
          );
        })}
      </div>
    </div>
  );
}

function ListCards({ items, onOpen }) {
  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 12 }}>
      {items.map(d => {
        const h = fmtListHeader(d.date);
        return (
          <button key={d.id} onClick={() => onOpen(d.id)} style={{ border: 0, cursor: "pointer", textAlign: "left",
            background: "var(--bg-normal)", borderRadius: 16, padding: "16px 18px", width: "100%",
            boxShadow: "0 1px 3px rgba(23,23,25,.06), inset 0 0 0 1px var(--line-alternative)" }}>
            <div style={{ display: "flex", alignItems: "baseline", gap: 8 }}>
              <span style={{ font: "800 20px var(--font-sans)", color: "var(--text-strong)", letterSpacing: "-0.02em" }}>{h.md} {h.day}일</span>
              <span style={{ font: "500 12px var(--font-sans)", color: "var(--text-assistive)" }}>{h.wk}요일</span>
              {d.status === "DRAFT" && <span style={{ marginLeft: "auto" }}><Tag color="neutral">임시</Tag></span>}
            </div>
            <div style={{ font: "400 14px/1.6 var(--font-sans)", color: "var(--text-neutral)", marginTop: 8,
              display: "-webkit-box", WebkitLineClamp: 2, WebkitBoxOrient: "vertical", overflow: "hidden" }}>{preview(d.content)}</div>
          </button>
        );
      })}
    </div>
  );
}

function ListCompact({ items, onOpen }) {
  return (
    <div>
      {items.map((d, i) => {
        const h = fmtListHeader(d.date);
        return (
          <React.Fragment key={d.id}>
            <button onClick={() => onOpen(d.id)} style={{ display: "flex", gap: 14, padding: "16px 2px", border: 0,
              background: "none", cursor: "pointer", textAlign: "left", width: "100%", alignItems: "flex-start" }}>
              <div style={{ flexShrink: 0, width: 36, textAlign: "center" }}>
                <div style={{ font: "800 18px var(--font-sans)", color: "var(--text-strong)" }}>{h.day}</div>
                <div style={{ font: "500 11px var(--font-sans)", color: "var(--text-assistive)" }}>{h.wk}</div>
              </div>
              <div style={{ flex: 1, minWidth: 0 }}>
                {d.status === "DRAFT" && <Tag color="neutral" style={{ marginBottom: 4 }}>임시</Tag>}
                <div style={{ font: "400 14px/1.55 var(--font-sans)", color: "var(--text-neutral)",
                  display: "-webkit-box", WebkitLineClamp: 2, WebkitBoxOrient: "vertical", overflow: "hidden" }}>{preview(d.content)}</div>
              </div>
              <Icon name="chevronRight" size={16} style={{ color: "var(--text-assistive)", flexShrink: 0, marginTop: 4 }} />
            </button>
            {i < items.length - 1 && <Divider />}
          </React.Fragment>
        );
      })}
    </div>
  );
}

Object.assign(window, { RcEditor: Editor, RcDetail: Detail, RcList: List });
