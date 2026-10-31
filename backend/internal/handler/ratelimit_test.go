package handler

import (
	"testing"
	"time"
)

func TestRateLimiterBlocksAfterLimit(t *testing.T) {
	l := NewRateLimiter(2, time.Minute)

	for i := 0; i < 2; i++ {
		if ok, _ := l.Allow("user"); !ok {
			t.Fatalf("запрос %d должен проходить", i+1)
		}
	}
	ok, retry := l.Allow("user")
	if ok {
		t.Fatal("третий запрос должен быть отклонён")
	}
	if retry <= 0 || retry > time.Minute {
		t.Errorf("retry-after вне окна: %v", retry)
	}
}

func TestRateLimiterKeysAreIndependent(t *testing.T) {
	l := NewRateLimiter(1, time.Minute)

	if ok, _ := l.Allow("a"); !ok {
		t.Fatal("первый запрос a должен проходить")
	}
	if ok, _ := l.Allow("b"); !ok {
		t.Fatal("лимит одного ключа не должен влиять на другой")
	}
}

func TestRateLimiterWindowExpires(t *testing.T) {
	l := NewRateLimiter(1, 30*time.Millisecond)

	if ok, _ := l.Allow("k"); !ok {
		t.Fatal("первый запрос должен проходить")
	}
	time.Sleep(50 * time.Millisecond)
	if ok, _ := l.Allow("k"); !ok {
		t.Fatal("после окна слот должен освободиться")
	}
}