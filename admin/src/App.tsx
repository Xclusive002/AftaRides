import { useEffect, useMemo, useState, type FormEvent, type ReactNode } from 'react'
import {
  Activity, ArrowRight, ArrowUpRight, CarFront, Check, ChevronDown, CircleDollarSign,
  Clock3, LayoutDashboard, LogOut, Menu, Search, ShieldCheck, Users,
} from 'lucide-react'
import {
  browserLocalPersistence, onAuthStateChanged, setPersistence, signInWithEmailAndPassword,
  signOut, type User,
} from 'firebase/auth'
import {
  collection, onSnapshot, orderBy, query, type DocumentData, type QuerySnapshot,
} from 'firebase/firestore'
import { Link, Navigate, NavLink, Outlet, Route, Routes, useLocation } from 'react-router-dom'
import { auth, db, firebaseConfigured } from './firebase'

type Ride = {
  id: string; riderId?: string; driverId?: string | null
  pickup?: { address?: string; lat?: number; lng?: number } | string
  dropoff?: { address?: string; lat?: number; lng?: number } | string
  status?: string; fare?: number; paid?: boolean; paystackReference?: string
  createdAt?: { seconds?: number } | Date | string
}
type Driver = { id: string; name?: string; email?: string; online?: boolean; lat?: number; lng?: number; updatedAt?: unknown }
type UserRecord = { id: string; name?: string; email?: string; role?: string }
type LoadState<T> = { data: T; loading: boolean; error: string }

function useCollection<T,>(name: string, sortField?: string): LoadState<T[]> {
  const [data, setData] = useState<T[]>([])
  const [loading, setLoading] = useState(Boolean(db))
  const [error, setError] = useState(db ? '' : 'Firebase is not configured.')
  useEffect(() => {
    if (!db) return
    const source = sortField ? query(collection(db, name), orderBy(sortField, 'desc')) : collection(db, name)
    return onSnapshot(source, (snapshot: QuerySnapshot<DocumentData>) => {
      setData(snapshot.docs.map((document) => ({ id: document.id, ...document.data() }) as T))
      setLoading(false)
      setError('')
    }, (reason) => {
      setError(reason.message || 'Could not load data.')
      setLoading(false)
    })
  }, [name, sortField])
  return { data, loading, error: db ? error : 'Firebase is not configured.' }
}

function App() {
  const [user, setUser] = useState<User | null>(null)
  const [authLoading, setAuthLoading] = useState(Boolean(auth))
  useEffect(() => {
    if (!auth) return
    return onAuthStateChanged(auth, (nextUser) => {
    setUser(nextUser)
    setAuthLoading(false)
    })
  }, [])
  return <Routes>
    <Route path="/login" element={user ? <Navigate to="/" replace /> : <LoginPage />} />
    <Route element={<RequireAuth user={user} loading={authLoading} />}>
      <Route element={<AdminLayout user={user} />}>
        <Route index element={<DashboardPage />} />
        <Route path="rides" element={<RidesPage />} />
        <Route path="drivers" element={<DriversPage />} />
        <Route path="payments" element={<PaymentsPage />} />
      </Route>
    </Route>
    <Route path="*" element={<Navigate to={user ? '/' : '/login'} replace />} />
  </Routes>
}

function RequireAuth({ user, loading }: { user: User | null; loading: boolean }) {
  const location = useLocation()
  if (!firebaseConfigured) return <SetupPage />
  if (loading) return <FullScreenLoading label="Checking admin session" />
  return user ? <Outlet /> : <Navigate to="/login" replace state={{ from: location.pathname }} />
}

function FullScreenLoading({ label }: { label: string }) {
  return <div className="screen-state"><span className="spinner" /><p>{label}…</p></div>
}

function SetupPage() {
  return <div className="setup-screen"><div className="login-brand"><span className="brand-mark">A</span><span>Afta<span>Rides</span></span></div><div className="setup-card"><ShieldCheck size={34} /><h1>Connect your Firebase project</h1><p>Set the Firebase client values in <code>admin/.env.local</code> to enable admin authentication and live data.</p></div></div>
}

function LoginPage() {
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(false)
  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault(); setError(''); setLoading(true)
    try {
      if (!auth) throw new Error('Firebase is not configured.')
      await setPersistence(auth, browserLocalPersistence)
      await signInWithEmailAndPassword(auth, email.trim(), password)
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : 'Unable to sign in.')
    } finally { setLoading(false) }
  }
  if (!firebaseConfigured) return <SetupPage />
  return <div className="login-screen">
    <div className="login-brand"><span className="brand-mark">A</span><span>Afta<span>Rides</span></span></div>
    <form className="login-card" onSubmit={submit}>
      <div className="eyebrow">ADMIN CONSOLE</div><h1>Welcome back</h1><p>Sign in to manage your ride network.</p>
      <label>Email address<input type="email" autoComplete="username" required value={email} onChange={(event) => setEmail(event.target.value)} placeholder="admin@aftarides.com" /></label>
      <label>Password<input type="password" autoComplete="current-password" required value={password} onChange={(event) => setPassword(event.target.value)} placeholder="Enter your password" /></label>
      {error && <div className="error-box" role="alert">{error}</div>}
      <button className="primary-button full-button" disabled={loading}>{loading ? <><span className="button-spinner" /> Signing in…</> : <>Sign in <ArrowRight size={17} /></>}</button>
      <div className="secure-note"><ShieldCheck size={15} /> Secure Firebase authentication</div>
    </form>
    <div className="login-foot">© {new Date().getFullYear()} AftaRides · Admin portal</div>
  </div>
}

const navItems = [
  { to: '/', label: 'Dashboard', icon: LayoutDashboard, end: true },
  { to: '/rides', label: 'Rides', icon: CarFront },
  { to: '/drivers', label: 'Drivers', icon: Users },
  { to: '/payments', label: 'Payments', icon: CircleDollarSign },
]

function AdminLayout({ user }: { user: User | null }) {
  const [mobileOpen, setMobileOpen] = useState(false)
  const location = useLocation()
  const activeTitle = navItems.find((item) => item.to === location.pathname)?.label ?? 'Dashboard'
  async function logout() { if (auth) await signOut(auth) }
  return <div className="admin-shell">
    {mobileOpen && <button className="mobile-scrim" aria-label="Close menu" onClick={() => setMobileOpen(false)} />}
    <aside className={`sidebar ${mobileOpen ? 'sidebar-open' : ''}`}>
      <Link to="/" className="brand"><span className="brand-mark">A</span><span>Afta<span>Rides</span></span></Link>
      <div className="workspace-label">WORKSPACE</div>
      <nav>{navItems.map(({ to, label, icon: Icon, end }) => <NavLink key={to} to={to} end={end} onClick={() => setMobileOpen(false)} className={({ isActive }: { isActive: boolean }) => `nav-link ${isActive ? 'nav-active' : ''}`}><Icon size={19} /><span>{label}</span>{label === 'Rides' && <span className="nav-live-dot" />}</NavLink>)}</nav>
      <div className="sidebar-bottom"><div className="support-box"><div className="support-icon"><ShieldCheck size={17} /></div><div><strong>Admin workspace</strong><span>Live operations enabled</span></div></div><button className="user-row" onClick={logout}><span className="avatar">{user?.email?.[0]?.toUpperCase() ?? 'A'}</span><span className="user-info"><strong>{user?.displayName || 'Administrator'}</strong><small>{user?.email}</small></span><LogOut size={17} /></button></div>
    </aside>
    <main className="main-panel">
      <header className="topbar"><button className="menu-button" onClick={() => setMobileOpen(true)} aria-label="Open menu"><Menu /></button><div className="topbar-title"><span>Operations</span><ChevronDown size={14} /><strong>{activeTitle}</strong></div><div className="topbar-right"><span className="live-indicator"><i /> Live data</span><span className="topbar-divider" /><div className="topbar-admin"><span className="avatar small-avatar">{user?.email?.[0]?.toUpperCase() ?? 'A'}</span><span>{user?.displayName || 'Admin'}</span></div></div></header>
      <div className="page-content"><Outlet /></div>
    </main>
  </div>
}

function PageHeading({ eyebrow, title, description, action }: { eyebrow: string; title: string; description: string; action?: ReactNode }) {
  return <div className="page-heading"><div><div className="eyebrow">{eyebrow}</div><h1>{title}</h1><p>{description}</p></div>{action}</div>
}

function StateMessage({ loading, error, empty, children }: { loading: boolean; error: string; empty?: boolean; children?: ReactNode }) {
  if (loading) return <div className="table-state"><span className="spinner" /><span>Loading live data…</span></div>
  if (error) return <div className="table-state error-state"><Activity size={22} /><strong>Couldn’t load data</strong><span>{error}</span></div>
  if (empty) return <div className="table-state"><span className="empty-icon"><Search size={20} /></span><strong>No records yet</strong><span>New records will appear here automatically.</span></div>
  return <>{children}</>
}

function DashboardPage() {
  const riders = useCollection<UserRecord>('users')
  const drivers = useCollection<Driver>('drivers')
  const rides = useCollection<Ride>('rides')
  const loading = riders.loading || drivers.loading || rides.loading
  const error = riders.error || drivers.error || rides.error
  const riderCount = riders.data.filter((record) => record.role === 'rider').length
  const driverCount = drivers.data.length
  const onlineCount = drivers.data.filter((driver) => driver.online).length
  const revenue = rides.data.filter((ride) => ride.paid).reduce((sum, ride) => sum + (Number(ride.fare) || 0), 0)
  const activeRides = rides.data.filter((ride) => ['requested', 'accepted', 'arriving', 'ongoing'].includes(ride.status ?? '')).length
  const recentRides = [...rides.data].sort((a, b) => timestamp(b.createdAt) - timestamp(a.createdAt)).slice(0, 5)
  return <>
    <PageHeading eyebrow="OVERVIEW" title="Dashboard" description="Here’s what’s happening across your ride network." action={<span className="updated-pill"><i /> Firestore connected</span>} />
    {error && <div className="error-box page-error">{error}</div>}
    <div className="metric-grid">
      <MetricCard label="Total riders" value={loading ? '—' : riderCount.toLocaleString()} icon={<Users />} tone="green" foot="Registered accounts" />
      <MetricCard label="Drivers online" value={loading ? '—' : `${onlineCount} / ${driverCount}`} icon={<CarFront />} tone="blue" foot="Available right now" />
      <MetricCard label="Total rides" value={loading ? '—' : rides.data.length.toLocaleString()} icon={<Activity />} tone="purple" foot={`${activeRides} active rides`} />
      <MetricCard label="Revenue received" value={loading ? '—' : money(revenue)} icon={<CircleDollarSign />} tone="amber" foot="Paid rides · NGN" />
    </div>
    <div className="content-grid dashboard-grid">
      <section className="panel recent-panel"><div className="panel-heading"><div><h2>Recent rides</h2><p>Latest activity from your network</p></div><Link to="/rides" className="text-link">View all <ArrowRight size={15} /></Link></div><StateMessage loading={rides.loading} error={rides.error} empty={!rides.loading && !rides.error && recentRides.length === 0}><RideTable rides={recentRides} compact /></StateMessage></section>
      <section className="panel online-panel"><div className="panel-heading"><div><h2>Driver availability</h2><p>Live fleet status</p></div><span className="live-indicator"><i /> Live</span></div>
        {drivers.loading ? <div className="mini-loading"><span className="spinner" />Loading drivers</div> : drivers.error ? <div className="inline-error">{drivers.error}</div> : <><div className="availability-number">{onlineCount}<span> / {driverCount} online</span></div><div className="availability-track"><i style={{ width: `${driverCount ? (onlineCount / driverCount) * 100 : 0}%` }} /></div><div className="availability-legend"><span><i className="online-dot" /> Online</span><span><i className="offline-dot" /> Offline</span></div><div className="driver-preview">{drivers.data.filter((driver) => driver.online).slice(0, 4).map((driver) => <div className="driver-preview-row" key={driver.id}><span className="avatar driver-avatar">{(driver.name || driver.email || 'D')[0].toUpperCase()}</span><span><strong>{driver.name || driver.email || `Driver ${driver.id.slice(0, 6)}`}</strong><small>Available for trips</small></span><i className="online-dot" /></div>)}{onlineCount === 0 && <div className="quiet-empty">No drivers are currently online.</div>}</div><Link to="/drivers" className="panel-bottom-link">View driver fleet <ArrowRight size={15} /></Link></>}
      </section>
    </div>
    <div className="bottom-note"><span className="note-icon"><ShieldCheck size={17} /></span><span><strong>Operations at a glance</strong><small>Counts and tables update in real time from Firestore.</small></span><span className="note-live"><i /> Connected</span></div>
  </>
}

function MetricCard({ label, value, icon, tone, foot }: { label: string; value: string; icon: ReactNode; tone: string; foot: string }) {
  return <article className="metric-card"><div className="metric-top"><span>{label}</span><span className={`metric-icon ${tone}`}>{icon}</span></div><strong className="metric-value">{value}</strong><div className="metric-foot"><span className="metric-trend"><ArrowUpRight size={14} /></span>{foot}</div></article>
}

function RidesPage() {
  const { data, loading, error } = useCollection<Ride>('rides', 'createdAt')
  const [filter, setFilter] = useState('all')
  const [search, setSearch] = useState('')
  const filtered = useMemo(() => data.filter((ride) => (filter === 'all' || ride.status === filter) && `${ride.id} ${ride.riderId ?? ''} ${ride.driverId ?? ''} ${address(ride.pickup)} ${address(ride.dropoff)}`.toLowerCase().includes(search.toLowerCase())), [data, filter, search])
  return <><PageHeading eyebrow="LIVE OPERATIONS" title="Rides" description="Monitor every ride request and trip status in real time." action={<span className="updated-pill"><i /> Live updates</span>} /><section className="panel table-panel"><div className="table-toolbar"><div className="filter-tabs">{['all', 'requested', 'accepted', 'arriving', 'ongoing', 'completed'].map((status) => <button key={status} className={filter === status ? 'filter-active' : ''} onClick={() => setFilter(status)}>{titleCase(status)}</button>)}</div><label className="table-search"><Search size={16} /><input value={search} onChange={(event) => setSearch(event.target.value)} placeholder="Search rides" /></label></div><StateMessage loading={loading} error={error} empty={!loading && !error && filtered.length === 0}><RideTable rides={filtered} /></StateMessage></section></>
}

function RideTable({ rides, compact = false }: { rides: Ride[]; compact?: boolean }) {
  return <div className="table-scroll"><table><thead><tr><th>Ride</th><th>Rider</th><th>Pickup → destination</th><th>Status</th><th>Fare</th><th>{compact ? 'Created' : 'Payment'}</th></tr></thead><tbody>{rides.map((ride) => <tr key={ride.id}><td><span className="ride-id">#{ride.id.slice(0, 8)}</span><small className="cell-sub">{dateLabel(ride.createdAt)}</small></td><td><span className="cell-primary">{ride.riderId ? ride.riderId.slice(0, 10) : '—'}</span></td><td><div className="route-cell"><span>{address(ride.pickup) || 'Pickup not set'}</span><ArrowRight size={13} /><span>{address(ride.dropoff) || 'Destination not set'}</span></div></td><td><StatusBadge status={ride.status ?? 'unknown'} /></td><td className="fare-cell">{money(Number(ride.fare) || 0)}</td><td>{compact ? <span className="cell-sub">{timeLabel(ride.createdAt)}</span> : <PaymentBadge paid={ride.paid} />}</td></tr>)}</tbody></table></div>
}

function DriversPage() {
  const { data, loading, error } = useCollection<Driver>('drivers')
  const [search, setSearch] = useState('')
  const filtered = data.filter((driver) => `${driver.name ?? ''} ${driver.email ?? ''} ${driver.id}`.toLowerCase().includes(search.toLowerCase()))
  const online = filtered.filter((driver) => driver.online).length
  return <><PageHeading eyebrow="FLEET MANAGEMENT" title="Drivers" description="Review driver accounts and live availability." action={<span className="updated-pill"><i /> {online} online</span>} /><section className="panel table-panel"><div className="table-toolbar"><div className="table-summary"><span className="summary-mark"><Users size={17} /></span><span><strong>{loading ? '—' : filtered.length} drivers</strong><small>{online} currently online</small></span></div><label className="table-search"><Search size={16} /><input value={search} onChange={(event) => setSearch(event.target.value)} placeholder="Search drivers" /></label></div><StateMessage loading={loading} error={error} empty={!loading && !error && filtered.length === 0}><div className="table-scroll"><table><thead><tr><th>Driver</th><th>Driver ID</th><th>Availability</th><th>Last location</th><th>Updated</th></tr></thead><tbody>{filtered.map((driver) => <tr key={driver.id}><td><div className="person-cell"><span className="avatar driver-avatar">{(driver.name || driver.email || 'D')[0].toUpperCase()}</span><span><strong>{driver.name || 'Driver'}</strong><small>{driver.email || 'No email provided'}</small></span></div></td><td><span className="mono-id">{driver.id}</span></td><td><AvailabilityBadge online={Boolean(driver.online)} /></td><td>{typeof driver.lat === 'number' && typeof driver.lng === 'number' ? <span className="location-cell">{driver.lat.toFixed(4)}, {driver.lng.toFixed(4)}</span> : <span className="cell-sub">Location unavailable</span>}</td><td className="cell-sub">{dateLabel(driver.updatedAt)}</td></tr>)}</tbody></table></div></StateMessage></section></>
}

function PaymentsPage() {
  const { data, loading, error } = useCollection<Ride>('rides', 'createdAt')
  const [filter, setFilter] = useState<'all' | 'paid' | 'unpaid'>('all')
  const payments = data.filter((ride) => ride.paid || Number(ride.fare) > 0).filter((ride) => filter === 'all' || (filter === 'paid' ? ride.paid : !ride.paid))
  const total = payments.filter((ride) => ride.paid).reduce((sum, ride) => sum + (Number(ride.fare) || 0), 0)
  return <><PageHeading eyebrow="FINANCIALS" title="Payments" description="Track ride fares and Paystack payment references." action={<span className="revenue-pill"><CircleDollarSign size={17} /> {money(total)} received</span>} /><section className="panel table-panel"><div className="table-toolbar"><div className="filter-tabs"><button className={filter === 'all' ? 'filter-active' : ''} onClick={() => setFilter('all')}>All payments</button><button className={filter === 'paid' ? 'filter-active' : ''} onClick={() => setFilter('paid')}>Paid</button><button className={filter === 'unpaid' ? 'filter-active' : ''} onClick={() => setFilter('unpaid')}>Unpaid</button></div><div className="payment-count"><Clock3 size={15} /> {payments.length} records</div></div><StateMessage loading={loading} error={error} empty={!loading && !error && payments.length === 0}><div className="table-scroll"><table><thead><tr><th>Ride</th><th>Rider</th><th>Amount</th><th>Status</th><th>Paystack reference</th><th>Completed</th></tr></thead><tbody>{payments.map((ride) => <tr key={ride.id}><td><span className="ride-id">#{ride.id.slice(0, 8)}</span></td><td><span className="cell-primary">{ride.riderId?.slice(0, 10) ?? '—'}</span></td><td className="fare-cell">{money(Number(ride.fare) || 0)}</td><td><PaymentBadge paid={ride.paid} /></td><td><span className="mono-id">{ride.paystackReference || '—'}</span></td><td className="cell-sub">{dateLabel(ride.createdAt)}</td></tr>)}</tbody></table></div></StateMessage></section></>
}

function StatusBadge({ status }: { status: string }) { return <span className={`status-badge status-${status.toLowerCase()}`}><i />{titleCase(status)}</span> }
function PaymentBadge({ paid }: { paid?: boolean }) { return <span className={`payment-badge ${paid ? 'is-paid' : 'is-unpaid'}`}>{paid ? <Check size={13} /> : <Clock3 size={13} />}{paid ? 'Paid' : 'Unpaid'}</span> }
function AvailabilityBadge({ online }: { online: boolean }) { return <span className={`availability-badge ${online ? 'is-online' : 'is-offline'}`}><i />{online ? 'Online' : 'Offline'}</span> }
function address(value: Ride['pickup']) { return typeof value === 'string' ? value : value?.address ?? '' }
function titleCase(value: string) { return value.charAt(0).toUpperCase() + value.slice(1) }
function money(amount: number) { return new Intl.NumberFormat('en-NG', { style: 'currency', currency: 'NGN', maximumFractionDigits: 0 }).format(amount) }
function timestamp(value: unknown): number { if (value && typeof value === 'object' && 'seconds' in value) return Number((value as { seconds?: number }).seconds ?? 0) * 1000; if (value instanceof Date) return value.getTime(); if (typeof value === 'string') return new Date(value).getTime() || 0; return 0 }
function dateLabel(value: unknown) { const time = timestamp(value); return time ? new Intl.DateTimeFormat('en-NG', { day: 'numeric', month: 'short', year: 'numeric' }).format(time) : '—' }
function timeLabel(value: unknown) { const time = timestamp(value); return time ? new Intl.DateTimeFormat('en-NG', { hour: 'numeric', minute: '2-digit' }).format(time) : '—' }

export default App
