const { Icon, IconButton, Avatar, Button, Logo, TextField, Divider, Tag } = window.WantedDesignSystem_f8da76;
const { fmtLong } = window.RC;

/* ════ LOGIN ════════════════════════════════════════════════ */
function Login({ onLogin }) {
  return (
    <div style={{ position: "relative", height: "100%", display: "flex", flexDirection: "column",
      padding: "0 30px", boxSizing: "border-box", overflow: "hidden",
      background: "radial-gradient(120% 80% at 82% -8%, #ECE2FF 0%, transparent 55%), radial-gradient(100% 70% at -12% 22%, #DBE7FF 0%, transparent 52%), linear-gradient(180deg, #FFFDF9, #FBF6FF)" }}>
      {/* floating blobs */}
      <div className="rc-float" style={{ position: "absolute", top: 90, right: -40, width: 150, height: 150, borderRadius: "50%",
        background: "radial-gradient(circle, rgba(139,92,246,.18), transparent 70%)", pointerEvents: "none" }} />
      <div className="rc-float" style={{ position: "absolute", bottom: 200, left: -50, width: 170, height: 170, borderRadius: "50%",
        background: "radial-gradient(circle, rgba(34,211,238,.16), transparent 70%)", pointerEvents: "none", animationDelay: ".8s" }} />

      <div style={{ flex: 1, display: "flex", flexDirection: "column", alignItems: "center", justifyContent: "center", gap: 14, position: "relative" }}>
        <window.RcPanda />

        {/* brand */}
        <div className="rc-rise" style={{ textAlign: "center", animationDelay: ".55s" }}>
          <div style={{ font: "700 50px var(--font-cute)", lineHeight: 1, letterSpacing: "0.01em",
            background: "linear-gradient(100deg, #7C3AED 0%, #3366FF 52%, #06B6D4 100%)",
            WebkitBackgroundClip: "text", backgroundClip: "text", WebkitTextFillColor: "transparent" }}>recorme</div>
          <div style={{ font: "700 15px var(--font-cute)", color: "var(--rc-violet)", marginTop: 12 }}>오늘 하루, 콕 찍어 기록해요</div>
        </div>
      </div>

      <div className="rc-rise" style={{ display: "flex", flexDirection: "column", gap: 10, paddingBottom: 34, position: "relative", animationDelay: ".7s" }}>
        <button onClick={onLogin} style={socialBtn("#FEE500", "#191600")}>
          <Icon name="bubbleFill" size={19} /><span>카카오로 시작하기</span>
        </button>
        <button onClick={onLogin} style={socialBtn("#fff", "var(--text-normal)", true)}>
          <span style={{ font: "800 16px var(--font-sans)", color: "#4285F4" }}>G</span><span>구글로 시작하기</span>
        </button>
        <div style={{ display: "flex", alignItems: "center", gap: 10, margin: "8px 0 2px" }}>
          <span style={{ flex: 1, height: 1, background: "var(--line-alternative)" }} />
          <span style={{ font: "500 12px var(--font-sans)", color: "var(--text-assistive)" }}>또는 이메일로</span>
          <span style={{ flex: 1, height: 1, background: "var(--line-alternative)" }} />
        </div>
        <TextField placeholder="name@email.com" leadingIcon={<Icon name="mail" size={18} />} />
        <button onClick={onLogin} style={{ ...socialBtn("linear-gradient(135deg, #8B5CF6, #3366FF)", "#fff"),
          boxShadow: "0 10px 24px rgba(101,65,242,.34)" }}>이메일로 계속하기</button>
        <div style={{ textAlign: "center", font: "500 13px var(--font-sans)", color: "var(--text-assistive)", marginTop: 6 }}>
          처음이신가요? <span style={{ color: "var(--rc-violet)", fontWeight: 700 }}>이메일로 회원가입</span>
        </div>
      </div>
    </div>
  );
}
function socialBtn(bg, color, border) {
  return {
    height: 52, borderRadius: 15, border: border ? "1px solid var(--line-normal,#dcdee3)" : 0, cursor: "pointer",
    background: bg, color, font: "600 15px var(--font-sans)", display: "flex", alignItems: "center",
    justifyContent: "center", gap: 8, width: "100%", boxShadow: border ? "0 2px 8px rgba(23,23,25,.05)" : "0 6px 16px rgba(23,23,25,.10)",
  };
}

/* ════ CALENDAR (main) ══════════════════════════════════════ */
function CalendarScreen({ layout, diaries, today, onPick, onProfile, onLogout }) {
  const user = window.RECORME_USER;
  return (
    <div style={{ paddingBottom: 24 }}>
      <window.RcAppBar onProfile={onProfile} onLogout={onLogout} />
      <div style={{ padding: "20px 20px 6px" }}>
        <div style={{ font: "500 14px var(--font-sans)", color: "var(--text-alternative)" }}>{user.nickname}님, 오늘의 하루는</div>
        <div style={{ font: "700 26px var(--font-display)", color: "var(--rc-ink, var(--text-strong))", letterSpacing: "-0.01em", marginTop: 4 }}>어떻게 기록할까요?</div>
      </div>
      <div style={{ padding: "10px 20px 0" }}>
        <window.RcCalendar layout={layout} diaries={diaries} today={today} onPick={onPick} />
      </div>
      <div style={{ display: "flex", gap: 16, padding: "20px 22px 0", font: "500 12px var(--font-sans)", color: "var(--text-assistive)" }}>
        <span style={{ display: "flex", alignItems: "center", gap: 5 }}>
          <span style={{ width: 7, height: 7, borderRadius: 4, background: "var(--accent-violet,#6541F2)" }} />기록한 날</span>
        <span style={{ display: "flex", alignItems: "center", gap: 5 }}>
          <span style={{ width: 7, height: 7, borderRadius: 4, background: "var(--text-assistive)" }} />임시 저장</span>
        <span style={{ display: "flex", alignItems: "center", gap: 5 }}>
          <span style={{ width: 9, height: 9, borderRadius: 5, background: "var(--primary-normal)" }} />오늘</span>
      </div>
    </div>
  );
}

/* ════ PROFILE ══════════════════════════════════════════════ */
function Profile({ onBack, onSave, onToast }) {
  const user = window.RECORME_USER;
  const [edit, setEdit] = React.useState(false);
  const [nick, setNick] = React.useState(user.nickname);
  const [bio, setBio] = React.useState(user.bio);

  const save = () => {
    user.nickname = nick.trim() || user.nickname;
    user.bio = bio;
    setEdit(false);
    onSave && onSave();
    onToast("프로필이 저장되었어요");
  };

  return (
    <div style={{ paddingBottom: 40 }}>
      <window.RcAppBar title="프로필" onBack={onBack}
        right={null} />
      <div style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 12, padding: "28px 24px 20px" }}>
        <div style={{ position: "relative" }}>
          <image-slot id="rc-avatar" shape="circle" placeholder="사진"
            style={{ width: 96, height: 96, display: "block", boxShadow: "inset 0 0 0 1px var(--line-alternative)" }}></image-slot>
          {edit && <span style={{ position: "absolute", right: -2, bottom: -2, width: 30, height: 30, borderRadius: 15,
            background: "var(--primary-normal)", color: "#fff", display: "flex", alignItems: "center", justifyContent: "center",
            boxShadow: "0 2px 8px rgba(0,0,0,.2)" }}><Icon name="pencilFill" size={15} /></span>}
        </div>
        {!edit && <>
          <div style={{ font: "700 20px var(--font-sans)", color: "var(--text-strong)" }}>{user.nickname}</div>
          <div style={{ font: "500 13px var(--font-sans)", color: "var(--text-assistive)", marginTop: -6 }}>{user.email}</div>
        </>}
      </div>

      {edit ? (
        <div style={{ padding: "0 24px", display: "flex", flexDirection: "column", gap: 16 }}>
          <Field label="닉네임"><TextField value={nick} onChange={(e) => setNick(e.target.value)} placeholder="닉네임" /></Field>
          <Field label="이메일">
            <div style={{ font: "500 15px var(--font-sans)", color: "var(--text-assistive)", padding: "12px 2px" }}>{user.email}</div>
          </Field>
          <Field label="자기소개">
            <textarea value={bio} maxLength={300} onChange={(e) => setBio(e.target.value)} rows={4}
              style={taStyle} placeholder="나를 한 문장으로 소개해보세요" />
            <div style={{ textAlign: "right", font: "400 12px var(--font-sans)", color: "var(--text-assistive)" }}>{bio.length}/300</div>
          </Field>
          <div style={{ display: "flex", gap: 8, marginTop: 6 }}>
            <Button variant="outlined" color="assistive" size="lg" fullWidth onClick={() => { setNick(user.nickname); setBio(user.bio); setEdit(false); }}>취소</Button>
            <Button variant="solid" color="primary" size="lg" fullWidth onClick={save}>저장</Button>
          </div>
        </div>
      ) : (
        <div style={{ padding: "0 24px" }}>
          <div style={{ background: "var(--bg-alternative,#F7F7F8)", borderRadius: 14, padding: "16px 18px",
            font: "400 15px/1.6 var(--font-sans)", color: "var(--text-neutral)" }}>
            {user.bio || "아직 소개가 없어요."}
          </div>
          <div style={{ marginTop: 24 }}>
            <Button variant="outlined" color="assistive" size="lg" fullWidth
              leadingIcon={<Icon name="pencil" size={18} />} onClick={() => setEdit(true)}>프로필 편집</Button>
          </div>
        </div>
      )}
    </div>
  );
}
function Field({ label, children }) {
  return (
    <div>
      <div style={{ font: "600 13px var(--font-sans)", color: "var(--text-neutral)", marginBottom: 6 }}>{label}</div>
      {children}
    </div>
  );
}
const taStyle = {
  width: "100%", boxSizing: "border-box", border: "1px solid var(--line-normal,#dcdee3)", borderRadius: 12,
  padding: "12px 14px", font: "400 15px/1.6 var(--font-sans)", color: "var(--text-normal)", resize: "none", outline: "none",
};

Object.assign(window, { RcLogin: Login, RcCalendarScreen: CalendarScreen, RcProfile: Profile, RcField: Field, rcTaStyle: taStyle });
