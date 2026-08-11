// Package store contains SQLite-backed table stores built on sqlc-generated
// queries.
package store

import (
	"context"
	"database/sql"
	"fmt"
	"sync"

	"github.com/OmarAly92/operator/backend/internal/domain"
	"github.com/OmarAly92/operator/backend/internal/storage/sqlite/gen"
)

// Store is the SQLite-backed persistence layer. It routes writes to a single
// writer connection (qw) and reads to a reader pool (qr) — see Open. writeMu
// guards the read-modify-write write methods (e.g. CreateSession's
// next-num-then-insert) so concurrent writes can't interleave them.
//
// CDC is captured by DB triggers (migration 0001), NOT by this layer: the store
// never writes change_log, it only reads it for the CDC poller.
type Store struct {
	writeDB *sql.DB
	readDB  *sql.DB
	qw      *gen.Queries // bound to the single writer connection
	qr      *gen.Queries // bound to the reader pool
	writeMu sync.Mutex

	// sessionIDInUse reports whether a candidate session ID is already claimed
	// in a namespace this store cannot see. Set by SetSessionIDInUse; nil means
	// the store is the sole authority on session IDs.
	sessionIDInUse func(context.Context, domain.SessionID) bool
}

// SetSessionIDInUse installs a probe consulted while allocating a session ID.
// Session IDs double as terminal-runtime session names, and that namespace is
// shared by every Operator instance on the machine — a tmux server outlives the
// daemon that populated it, so a fresh database allocating from 1 can hand out
// a name tmux still holds and the spawn fails at launch. The probe lets the
// allocator skip those.
//
// The probe answers yes/no with no error: whether an unanswerable probe means
// "free" or "taken" is a policy its owner decides, not the allocator. Wiring
// installs it after the runtime exists; tests and read-only openers leave it
// nil. It must be set before the store serves traffic.
func (s *Store) SetSessionIDInUse(fn func(context.Context, domain.SessionID) bool) {
	s.sessionIDInUse = fn
}

type conversationProjectionTxKey struct{}

// conversationWriter returns the transaction-bound query set when a provider
// event projection is in progress. Otherwise it acquires the ordinary single
// writer lock. This makes the existing focused store methods composable inside
// one archive+projection transaction without exposing SQLite transactions above
// the adapter boundary.
func (s *Store) conversationWriter(ctx context.Context) (*gen.Queries, func()) {
	if q, ok := ctx.Value(conversationProjectionTxKey{}).(*gen.Queries); ok && q != nil {
		return q, func() {}
	}
	s.writeMu.Lock()
	return s.qw, s.writeMu.Unlock
}

func (s *Store) conversationReader(ctx context.Context) *gen.Queries {
	if q, ok := ctx.Value(conversationProjectionTxKey{}).(*gen.Queries); ok && q != nil {
		return q
	}
	return s.qr
}

// NewStore wraps an opened writer + reader *sql.DB (see Open) as a Store.
func NewStore(writeDB, readDB *sql.DB) *Store {
	return &Store{
		writeDB: writeDB,
		readDB:  readDB,
		qw:      gen.New(writeDB),
		qr:      gen.New(readDB),
	}
}

// Close closes both pools.
func (s *Store) Close() error {
	err := s.writeDB.Close()
	if e := s.readDB.Close(); e != nil && err == nil {
		err = e
	}
	return err
}

// inTx runs fn inside a single write transaction on the writer connection,
// rolling back on error. The caller must already hold writeMu.
func (s *Store) inTx(ctx context.Context, what string, fn func(*gen.Queries) error) error {
	if q, ok := ctx.Value(conversationProjectionTxKey{}).(*gen.Queries); ok && q != nil {
		if err := fn(q); err != nil {
			return fmt.Errorf("%s: %w", what, err)
		}
		return nil
	}
	tx, err := s.writeDB.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("begin %s: %w", what, err)
	}
	defer func() { _ = tx.Rollback() }()
	if err := fn(s.qw.WithTx(tx)); err != nil {
		return fmt.Errorf("%s: %w", what, err)
	}
	return tx.Commit()
}
