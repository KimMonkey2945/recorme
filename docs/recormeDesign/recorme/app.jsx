const { Icon, BottomNavigation } = window.WantedDesignSystem_f8da76;

const TWEAK_DEFAULTS = /*EDITMODE-BEGIN*/{
  "calendarLayout": "dots",
  "editorLayout": "paper",
  "listLayout": "timeline",
  "entryFont": "serif"
}/*EDITMODE-END*/;

let UID = 100;
function newId() { return "d-n" + (++UID); }

function App() {
  const [t, setTweak] = useTweaks(TWEAK_DEFAULTS);
  const [loggedIn, setLoggedIn] = React.useState(false);
  const [tab, setTab] = React.useState("calendar");
  const [route, setRoute] = React.useState("calendar"); // calendar|list|editor|detail|profile
  const [diaries, setDiaries] = React.useState(window.RECORME_DIARIES);
  const [editorCtx, setEditorCtx] = React.useState(null); // {date, initial, mode, returnTo, id}
  const [detailId, setDetailId] = React.useState(null);
  const [dialog, setDialog] = React.useState(null);
  const [toast, setToast] = React.useState(null);
  const [, force] = React.useState(0);

  const today = window.RECORME_TODAY;
  const showToast = (msg, tone) => { setToast({ msg, tone }); clearTimeout(window.__rcT); window.__rcT = setTimeout(() => setToast(null), 2200); };
  const byDate = (date) => diaries.find(d => d.date === date);
  const byId = (id) => diaries.find(d => d.id === id);

  /* nav */
  const goTab = (k) => { setTab(k); setRoute(k); };
  const pickDate = (date) => {
    const d = byDate(date);
    if (d) { setDetailId(d.id); setRoute("detail"); }
    else { setEditorCtx({ date, initial: "", mode: "new", returnTo: "calendar" }); setRoute("editor"); }
  };
  const openDetail = (id) => { setDetailId(id); setRoute("detail"); };

  /* editor actions */
  const saveDraft = (text) => {
    const ex = editorCtx.id ? byId(editorCtx.id) : byDate(editorCtx.date);
    if (ex) setDiaries(ds => ds.map(d => d.id === ex.id ? { ...d, content: text, status: "DRAFT" } : d));
    else setDiaries(ds => [...ds, { id: newId(), date: editorCtx.date, content: text, status: "DRAFT", photos: [] }]);
    setRoute(editorCtx.returnTo === "detail" ? "detail" : "calendar");
    showToast("임시 저장되었어요");
  };
  const confirmRemember = (text) => {
    setDialog({
      kind: "remember",
      run: () => {
        const ex = editorCtx.id ? byId(editorCtx.id) : byDate(editorCtx.date);
        let id;
        if (ex) { id = ex.id; setDiaries(ds => ds.map(d => d.id === ex.id ? { ...d, content: text, status: "PENDING" } : d)); }
        else { id = newId(); setDiaries(ds => [...ds, { id, date: editorCtx.date, content: text, status: "PENDING", photos: [] }]); }
        setDialog(null); setDetailId(id); setRoute("detail");
        showToast("오늘을 기억했어요");
      },
    });
  };
  const cancelEditor = () => setRoute(editorCtx.returnTo === "detail" ? "detail" : "calendar");

  /* detail actions */
  const editDraft = () => {
    const d = byId(detailId);
    setEditorCtx({ date: d.date, initial: d.content, mode: "edit", returnTo: "detail", id: d.id });
    setRoute("editor");
  };
  const askDelete = () => setDialog({
    kind: "delete",
    run: () => {
      setDiaries(ds => ds.filter(d => d.id !== detailId));
      setDialog(null); setRoute("calendar"); setTab("calendar");
      showToast("기록을 삭제했어요");
    },
  });

  const logout = () => setDialog({
    kind: "logout",
    run: () => { setDialog(null); setLoggedIn(false); setRoute("calendar"); setTab("calendar"); },
  });

  if (!loggedIn) {
    return <div className="rc-app"><window.RcLogin onLogin={() => { setLoggedIn(true); setRoute("calendar"); setTab("calendar"); }} /></div>;
  }

  const fontVar = t.entryFont === "sans" ? "var(--font-sans)" : "var(--font-serene)";
  const showNav = route === "calendar" || route === "list";

  let screen;
  if (route === "editor") {
    screen = <window.RcEditor layout={t.editorLayout} date={editorCtx.date} initial={editorCtx.initial} mode={editorCtx.mode}
      onCancel={cancelEditor} onRegister={saveDraft} onConfirm={confirmRemember} />;
  } else if (route === "detail") {
    const d = byId(detailId);
    screen = d ? <window.RcDetail diary={d} onBack={() => setRoute(tab === "list" ? "list" : "calendar")}
      onEdit={editDraft} onDelete={askDelete} /> : null;
  } else if (route === "profile") {
    screen = <window.RcProfile onBack={() => setRoute(tab)} onSave={() => force(x => x + 1)} onToast={showToast} />;
  } else if (route === "list") {
    screen = <window.RcList layout={t.listLayout} diaries={diaries} onOpen={openDetail}
      onProfile={() => setRoute("profile")} onLogout={logout} />;
  } else {
    screen = <window.RcCalendarScreen layout={t.calendarLayout} diaries={diaries} today={today} onPick={pickDate}
      onProfile={() => setRoute("profile")} onLogout={logout} />;
  }

  return (
    <div className="rc-app" style={{ "--font-serif": fontVar }}>
      <div className="rc-screen" style={{ paddingBottom: showNav ? 0 : 0 }}>
        {screen}
      </div>

      {showNav && (
        <div className="rc-nav">
          <BottomNavigation value={tab} onChange={goTab} items={[
            { key: "calendar", label: "캘린더", icon: <Icon name="calendar" size={24} />, activeIcon: <Icon name="calendar" size={24} /> },
            { key: "list", label: "기록", icon: <Icon name="document" size={24} />, activeIcon: <Icon name="documentFill" size={24} /> },
          ]} />
        </div>
      )}

      <window.RcConfirm open={dialog?.kind === "remember"} icon="sparkle"
        title="오늘을 기억할까요?" body="기억한 기록은 감정 분석을 거치며, 이후에는 수정할 수 없어요."
        confirmLabel="기억하기" onConfirm={dialog?.run} onCancel={() => setDialog(null)} />
      <window.RcConfirm open={dialog?.kind === "delete"} icon="trash" tone="negative"
        title="이 기록을 삭제할까요?" body="삭제한 기록은 되돌릴 수 없어요. 같은 날짜에 다시 쓸 수 있어요."
        confirmLabel="삭제" onConfirm={dialog?.run} onCancel={() => setDialog(null)} />
      <window.RcConfirm open={dialog?.kind === "logout"} icon="externalLink"
        title="로그아웃 할까요?" confirmLabel="로그아웃" onConfirm={dialog?.run} onCancel={() => setDialog(null)} />

      <window.RcToast toast={toast} />

      <TweaksPanel>
        <TweakSection label="레이아웃 변형" />
        <TweakRadio label="캘린더" value={t.calendarLayout}
          options={[{ value: "dots", label: "점" }, { value: "heatmap", label: "타일" }, { value: "agenda", label: "아젠다" }]}
          onChange={(v) => setTweak("calendarLayout", v)} />
        <TweakRadio label="에디터" value={t.editorLayout}
          options={[{ value: "paper", label: "종이" }, { value: "clean", label: "카드" }, { value: "focus", label: "몰입" }]}
          onChange={(v) => setTweak("editorLayout", v)} />
        <TweakRadio label="목록" value={t.listLayout}
          options={[{ value: "timeline", label: "타임라인" }, { value: "cards", label: "카드" }, { value: "compact", label: "간결" }]}
          onChange={(v) => setTweak("listLayout", v)} />
        <TweakSection label="감성" />
        <TweakRadio label="기록 글꼴" value={t.entryFont}
          options={[{ value: "serif", label: "명조" }, { value: "sans", label: "고딕" }]}
          onChange={(v) => setTweak("entryFont", v)} />
      </TweaksPanel>
    </div>
  );
}

ReactDOM.createRoot(document.getElementById("root")).render(<App />);
