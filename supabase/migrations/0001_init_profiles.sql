-- =====================================================================
-- 0001_init_profiles.sql
-- record 사용자 프로필 + 소셜 회원가입 자동 생성 트리거 + RLS
-- (Supabase Auth 기반. Spring 설계의 users/social_accounts를 대체)
-- =====================================================================

-- ========== 프로필 (auth.users 1:1) ==========
create table public.profiles (
  id         uuid primary key references auth.users(id) on delete cascade,
  nickname   text not null,
  email      text,
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.profiles is 'record 사용자 프로필 (auth.users와 1:1)';

alter table public.profiles enable row level security;

-- 본인 프로필만 조회/수정 (insert는 트리거가 담당)
create policy "profiles_select_own"
  on public.profiles for select
  using ((select auth.uid()) = id);

create policy "profiles_update_own"
  on public.profiles for update
  using ((select auth.uid()) = id)
  with check ((select auth.uid()) = id);

-- ========== 소셜 회원가입 시 프로필 자동 생성 ==========
-- security definer + search_path='' (Supabase 권장 안전 패턴)
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, nickname, email, avatar_url)
  values (
    new.id,
    coalesce(
      new.raw_user_meta_data->>'name',
      new.raw_user_meta_data->>'full_name',
      new.raw_user_meta_data->>'nickname',
      new.raw_user_meta_data->>'user_name',
      split_part(coalesce(new.email, 'user'), '@', 1)
    ),
    new.email,
    coalesce(
      new.raw_user_meta_data->>'avatar_url',
      new.raw_user_meta_data->>'picture'
    )
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- 트리거로만 호출되도록 직접 실행 권한 회수
revoke execute on function public.handle_new_user() from anon, authenticated, public;
