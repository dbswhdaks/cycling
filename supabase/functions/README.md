# Supabase Edge Functions

## activate-subscription

클라이언트에서 직접 `subscriptions` 테이블을 쓰지 않고, 서버 함수에서 구독 상태를 갱신합니다.

### 배포

```bash
supabase functions deploy activate-subscription
```

### 로컬 실행

```bash
supabase functions serve activate-subscription --no-verify-jwt
```

### 필요 환경 변수

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `SUPABASE_SERVICE_ROLE_KEY`

