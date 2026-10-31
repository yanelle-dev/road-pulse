package handler

import (
	"net"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"time"
)

// RateLimiter — скользящее окно в памяти одного процесса.
type RateLimiter struct {
	mu     sync.Mutex
	limit  int
	window time.Duration
	hits   map[string][]time.Time
	nextGC time.Time
}

func NewRateLimiter(limit int, window time.Duration) *RateLimiter {
	return &RateLimiter{limit: limit, window: window, hits: make(map[string][]time.Time)}
}

// Allow возвращает false и время до освобождения слота, если лимит исчерпан.
func (l *RateLimiter) Allow(key string) (bool, time.Duration) {
	l.mu.Lock()
	defer l.mu.Unlock()

	now := time.Now()
	l.gc(now)

	recent := l.prune(l.hits[key], now)
	if len(recent) >= l.limit {
		l.hits[key] = recent
		return false, recent[0].Add(l.window).Sub(now)
	}
	l.hits[key] = append(recent, now)
	return true, 0
}

func (l *RateLimiter) prune(ts []time.Time, now time.Time) []time.Time {
	cut := now.Add(-l.window)
	i := 0
	for i < len(ts) && ts[i].Before(cut) {
		i++
	}
	return ts[i:]
}

func (l *RateLimiter) gc(now time.Time) {
	if now.Before(l.nextGC) {
		return
	}
	l.nextGC = now.Add(time.Minute)
	for k, ts := range l.hits {
		if recent := l.prune(ts, now); len(recent) == 0 {
			delete(l.hits, k)
		} else {
			l.hits[k] = recent
		}
	}
}

// clientIP берёт X-Forwarded-For (последнюю запись, добавленную доверенным прокси)
// только при trustProxy: иначе заголовок подделывается любым клиентом.
func clientIP(r *http.Request, trustProxy bool) string {
	if trustProxy {
		if parts := strings.Split(r.Header.Get("X-Forwarded-For"), ","); len(parts) > 0 {
			if ip := strings.TrimSpace(parts[len(parts)-1]); ip != "" {
				return ip
			}
		}
	}
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}

// RateLimit ограничивает запросы по пользователю из JWT-контекста, а для гостей — по IP.
// Ставится после OptionalAuth/RequireAuth, если лимит нужен per-user.
func RateLimit(l *RateLimiter, trustProxy bool) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			key := userIDFrom(r)
			if key == "" {
				key = "ip:" + clientIP(r, trustProxy)
			}
			if ok, retry := l.Allow(key); !ok {
				w.Header().Set("Retry-After", strconv.Itoa(int(retry.Seconds())+1))
				respondDetail(w, http.StatusTooManyRequests, "Слишком много запросов")
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}