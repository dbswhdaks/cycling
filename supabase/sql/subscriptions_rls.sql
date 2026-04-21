-- subscriptions 테이블을 클라이언트 직접 쓰기 금지하고
-- Edge Function(service_role) 경로만 쓰도록 제한하는 정책 예시

alter table public.subscriptions enable row level security;

drop policy if exists "subscriptions_select_own" on public.subscriptions;
drop policy if exists "subscriptions_insert_own" on public.subscriptions;
drop policy if exists "subscriptions_update_own" on public.subscriptions;
drop policy if exists "subscriptions_delete_own" on public.subscriptions;

create policy "subscriptions_select_own"
on public.subscriptions
for select
to authenticated
using (auth.uid() = user_id);

-- insert/update/delete 정책을 만들지 않으면
-- authenticated 사용자는 직접 쓰기 불가입니다.
-- service_role 키를 쓰는 Edge Function은 RLS를 우회해 쓰기 가능합니다.
