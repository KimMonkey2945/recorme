const { Icon, IconButton } = window.WantedDesignSystem_f8da76;
const { WEEK_KO, parseDate, toKey, pad } = window.RC;

function monthMatrix(year, month) {
  const first = new Date(year, month, 1);
  const start = first.getDay();
  const days = new Date(year, month + 1, 0).getDate();
  const cells = [];
  for (let i = 0; i < start; i++) cells.push(null);
  for (let d = 1; d <= days; d++) cells.push(d);
  while (cells.length % 7 !== 0) cells.push(null);
  return cells;
}

function Weekdays() {
  return (
    <div style={{ display: "grid", gridTemplateColumns: "repeat(7,1fr)", marginBottom: 6 }}>
      {WEEK_KO.map((w, i) => (
        <div key={w} style={{ textAlign: "center", font: "600 12px var(--font-sans)",
          color: i === 0 ? "var(--negative-normal)" : i === 6 ? "var(--primary-normal)" : "var(--text-assistive)" }}>{w}</div>
      ))}
    </div>
  );
}

function MonthHeader({ year, month, onPrev, onNext }) {
  return (
    <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", padding: "4px 2px 14px" }}>
      <div style={{ font: "700 22px var(--font-sans)", color: "var(--text-strong)", letterSpacing: "-0.02em" }}>
        {year}년 <span style={{ color: "var(--primary-normal)" }}>{month + 1}월</span>
      </div>
      <div style={{ display: "flex", gap: 2 }}>
        <IconButton styleType="normal" onClick={onPrev}><Icon name="chevronLeft" size={22} /></IconButton>
        <IconButton styleType="normal" onClick={onNext}><Icon name="chevronRight" size={22} /></IconButton>
      </div>
    </div>
  );
}

function Calendar({ layout, diaries, today, onPick }) {
  const td = parseDate(today);
  const [cur, setCur] = React.useState({ y: td.getFullYear(), m: td.getMonth() });
  const map = {}; diaries.forEach(d => { map[d.date] = d.status; });
  const cells = monthMatrix(cur.y, cur.m);
  const prev = () => setCur(c => c.m === 0 ? { y: c.y - 1, m: 11 } : { y: c.y, m: c.m - 1 });
  const next = () => setCur(c => c.m === 11 ? { y: c.y + 1, m: 0 } : { y: c.y, m: c.m + 1 });
  const keyOf = (d) => `${cur.y}-${pad(cur.m + 1)}-${pad(d)}`;
  const isToday = (d) => keyOf(d) === today;
  const dow = (idx) => idx % 7;

  function Cell({ d, idx }) {
    if (!d) return <div />;
    const k = keyOf(d);
    const status = map[k];
    const todayCell = isToday(d);
    const future = parseDate(k) > td;
    const sun = dow(idx) === 0, sat = dow(idx) === 6;
    const numColor = todayCell ? "#fff" : future ? "var(--text-disable,#bbb)"
      : sun ? "var(--negative-normal)" : sat ? "var(--primary-normal)" : "var(--text-normal)";

    if (layout === "heatmap") {
      const filled = !!status;
      return (
        <button onClick={() => onPick(k)} disabled={future} style={{
          aspectRatio: "1", border: 0, cursor: future ? "default" : "pointer",
          borderRadius: 12, display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", gap: 2,
          background: todayCell ? "var(--primary-normal)"
            : filled ? (status === "DRAFT" ? "var(--bg-alternative,#EDEEF1)" : "var(--primary-assistive,#E9F0FF)") : "transparent",
          color: numColor, font: "600 14px var(--font-sans)", transition: "transform .12s",
        }}>
          <span>{d}</span>
          {filled && !todayCell && <span style={{ width: 4, height: 4, borderRadius: 2,
            background: status === "DRAFT" ? "var(--text-assistive)" : "var(--accent-violet,#6541F2)" }} />}
        </button>
      );
    }
    // default: dots
    return (
      <button onClick={() => onPick(k)} disabled={future} style={{
        aspectRatio: "1", border: 0, background: "none", cursor: future ? "default" : "pointer",
        display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", gap: 3, padding: 0,
      }}>
        <span style={{
          width: 32, height: 32, borderRadius: 16, display: "flex", alignItems: "center", justifyContent: "center",
          background: todayCell ? "var(--primary-normal)" : "transparent",
          color: numColor, font: "600 14px var(--font-sans)",
          boxShadow: status && !todayCell ? "inset 0 0 0 1px var(--line-alternative)" : "none",
        }}>{d}</span>
        <span style={{ height: 5, display: "flex", alignItems: "center" }}>
          {status && <span style={{ width: 5, height: 5, borderRadius: 3,
            background: status === "DRAFT" ? "var(--text-assistive)" : "var(--accent-violet,#6541F2)" }} />}
        </span>
      </button>
    );
  }

  const grid = (
    <div style={{ display: "grid", gridTemplateColumns: "repeat(7,1fr)", rowGap: layout === "heatmap" ? 4 : 2 }}>
      {cells.map((d, i) => <Cell key={i} d={d} idx={i} />)}
    </div>
  );

  if (layout === "agenda") {
    const month = diaries
      .filter(d => { const dt = parseDate(d.date); return dt.getFullYear() === cur.y && dt.getMonth() === cur.m; })
      .sort((a, b) => b.date < a.date ? -1 : 1);
    return (
      <div>
        <MonthHeader year={cur.y} month={cur.m} onPrev={prev} onNext={next} />
        <Weekdays />
        {grid}
        <div style={{ height: 8, background: "var(--bg-alternative,#F2F3F5)", margin: "20px -20px 0", borderRadius: 1 }} />
        <div style={{ font: "700 14px var(--font-sans)", color: "var(--text-neutral)", padding: "18px 2px 10px" }}>
          이번 달 기록 <span style={{ color: "var(--primary-normal)" }}>{month.length}</span>
        </div>
        <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
          {month.length === 0 && <div style={{ font: "400 13px var(--font-sans)", color: "var(--text-assistive)", padding: "6px 2px 20px" }}>아직 이번 달 기록이 없어요.</div>}
          {month.map(d => {
            const dt = parseDate(d.date);
            return (
              <button key={d.id} onClick={() => onPick(d.date)} style={{
                display: "flex", alignItems: "center", gap: 14, padding: "12px 12px", border: 0, cursor: "pointer",
                background: "var(--bg-alternative,#F7F7F8)", borderRadius: 12, textAlign: "left", width: "100%",
              }}>
                <div style={{ flexShrink: 0, width: 40, textAlign: "center" }}>
                  <div style={{ font: "700 18px var(--font-sans)", color: "var(--text-strong)" }}>{dt.getDate()}</div>
                  <div style={{ font: "500 11px var(--font-sans)", color: "var(--text-assistive)" }}>{WEEK_KO[dt.getDay()]}</div>
                </div>
                <div style={{ flex: 1, minWidth: 0, font: "400 14px var(--font-sans)", color: "var(--text-neutral)",
                  overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>
                  {d.status === "DRAFT" && <span style={{ color: "var(--text-assistive)", fontWeight: 600, marginRight: 6 }}>임시</span>}
                  {d.content.replace(/\n/g, " ")}
                </div>
                <Icon name="chevronRight" size={16} style={{ color: "var(--text-assistive)", flexShrink: 0 }} />
              </button>
            );
          })}
        </div>
      </div>
    );
  }

  return (
    <div>
      <MonthHeader year={cur.y} month={cur.m} onPrev={prev} onNext={next} />
      <Weekdays />
      {grid}
    </div>
  );
}

window.RcCalendar = Calendar;
