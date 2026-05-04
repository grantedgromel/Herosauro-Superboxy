// Veblen — shared components
const { useState, useEffect, useMemo, useRef } = React;

// ============ Grade Badge ============
const GRADE_ORDER = ["excellent", "great", "good", "fair", "poor"];
const GRADE_LETTER = { excellent: "A", great: "B", good: "C", fair: "D", poor: "F" };
const GRADE_LABEL = { excellent: "Excellent", great: "Great", good: "Good", fair: "Fair", poor: "Poor" };

function GradeBadge({ grade, large, suffix }) {
  return (
    <div className={`grade ${grade} ${large ? "large" : ""}`}>
      <div className="word">{GRADE_LABEL[grade]}</div>
      {suffix && <div className="suffix">{suffix}</div>}
    </div>
  );
}

// ============ Sparkline ============
function Sparkline({ data, color = "var(--ink)", height = 28, fill = false }) {
  const w = 200, h = height;
  const min = Math.min(...data), max = Math.max(...data);
  const range = max - min || 1;
  const pts = data.map((v, i) => {
    const x = (i / (data.length - 1)) * w;
    const y = h - ((v - min) / range) * (h - 4) - 2;
    return [x, y];
  });
  const line = pts.map(([x,y], i) => (i===0 ? `M${x},${y}` : `L${x},${y}`)).join(" ");
  const area = `${line} L${w},${h} L0,${h} Z`;
  const last = pts[pts.length-1];
  return (
    <svg className="spark" viewBox={`0 0 ${w} ${h}`} preserveAspectRatio="none">
      {fill && <path d={area} fill={color} opacity="0.08" />}
      <path d={line} fill="none" stroke={color} strokeWidth="1.2" vectorEffect="non-scaling-stroke" />
      <circle cx={last[0]} cy={last[1]} r="2" fill={color} />
    </svg>
  );
}

// ============ Garment placeholder ============
function GarmentSwatch({ id, label, category }) {
  // deterministic angle from id
  let h = 0;
  for (let i = 0; i < id.length; i++) h = (h * 31 + id.charCodeAt(i)) >>> 0;
  const stripeAngle = (h % 60) - 30;
  const fills = [
    ["#D7CFB8", "#C8BFA0"],
    ["#C2B89E", "#B0A481"],
    ["#BBB199", "#A39871"],
  ];
  const tone = Math.abs((h >>> 6) % fills.length);
  const pair = fills[tone] || fills[0];
  const a = pair[0];
  const b = pair[1];
  return (
    <svg viewBox="0 0 120 160" preserveAspectRatio="xMidYMid slice">
      <defs>
        <pattern id={`p-${id}`} width="8" height="8" patternUnits="userSpaceOnUse" patternTransform={`rotate(${stripeAngle})`}>
          <rect width="8" height="8" fill={a} />
          <rect width="4" height="8" fill={b} />
        </pattern>
      </defs>
      <rect width="120" height="160" fill={`url(#p-${id})`} />
      <rect x="8" y="8" width="104" height="144" fill="none" stroke="rgba(26,24,21,0.25)" strokeDasharray="2 3" />
      <text x="60" y="80" textAnchor="middle" fontFamily="IBM Plex Mono, monospace" fontSize="7" letterSpacing="1.5" fill="rgba(26,24,21,0.55)">
        {(category || "ITEM").toUpperCase()}
      </text>
      <text x="60" y="92" textAnchor="middle" fontFamily="IBM Plex Mono, monospace" fontSize="6" letterSpacing="1" fill="rgba(26,24,21,0.4)">
        PHOTOGRAPHY · TK
      </text>
    </svg>
  );
}

// ============ Deal Card ============
// ============ Size rail ============
function SizeRail({ sizes, kind, large, onPick, picked }) {
  if (!sizes || !sizes.length) return null;
  return (
    <div className={`size-rail ${large ? "large" : ""}`}>
      {sizes.map(([label, status]) => (
        <button
          key={label}
          type="button"
          className={`size-pill ${status} ${picked === label ? "picked" : ""}`}
          disabled={status === "out"}
          onClick={(e) => { e.stopPropagation(); onPick && onPick(label); }}
          title={status === "out" ? "Sold out" : status === "low" ? "Low stock" : "Available"}
        >
          {label}
        </button>
      ))}
    </div>
  );
}

function SizeSummary({ sizes }) {
  if (!sizes || !sizes.length) return null;
  const inN = sizes.filter(s => s[1] === "in").length;
  const lowN = sizes.filter(s => s[1] === "low").length;
  const outN = sizes.filter(s => s[1] === "out").length;
  const lowLabels = sizes.filter(s => s[1] === "low").map(s => s[0]).join(", ");
  return (
    <div className="size-summary">
      <span><b className="tnum">{inN}</b> in</span>
      {lowN > 0 && <span className="low">· <b className="tnum">{lowN}</b> low {lowLabels && <span className="muted">({lowLabels})</span>}</span>}
      {outN > 0 && <span className="muted">· {outN} out</span>}
    </div>
  );
}

function DealCard({ item, onOpen, onSave, saved }) {
  return (
    <div className="deal-card" onClick={() => onOpen && onOpen(item)}>
      <div className="deal-img">
        <GarmentSwatch id={item.id} category={item.category} />
        {item.flag && (
          <div className="deal-flag">⚠ {item.flag}</div>
        )}
      </div>
      <div className="deal-body">
        <h3 className="deal-name"><span className="deal-name-brand">{item.brand}</span> {item.name}</h3>
        <div className="deal-price-row">
          <span className="deal-price-now">${item.price}</span>
          <span className="deal-price-was">${item.was}</span>
          <span className="deal-discount">−{item.discount}%</span>
        </div>
        <div className={`deal-grade-line ${item.grade}`}>
          <span className="word">{GRADE_LABEL[item.grade]}</span>
          <span className="suffix">price for value</span>
        </div>
        <SizeRail sizes={item.sizes} kind={item.sizeKind} />
      </div>
    </div>
  );
}

// ============ Masthead ============
function Masthead({ page, onNav, columns, onColumns }) {
  return (
    <header className="masthead">
      <h1 className="masthead-title" onClick={() => onNav("browse")} style={{cursor:"pointer"}}>
        Veblen
        <span className="small">For the Rational Consumer</span>
      </h1>
      <nav className="masthead-nav">
        <button className={page === "browse" ? "active" : ""} onClick={() => onNav("browse")}>Browse</button>
        <button className={page === "saved" ? "active" : ""} onClick={() => onNav("saved")}>Saved · Alerts</button>
        <button className={page === "method" ? "active" : ""} onClick={() => onNav("method")}>Methodology</button>
        {page === "browse" && onColumns && (
          <div className="col-toggle" role="group" aria-label="Items per row">
            <span className="col-toggle-label">View</span>
            {[2, 4, 6].map(n => (
              <button
                key={n}
                className={columns === n ? "active" : ""}
                onClick={() => onColumns(n)}
                aria-label={`${n} per row`}
                title={`${n} per row`}
              >
                <ColIcon n={n} />
              </button>
            ))}
          </div>
        )}
      </nav>
    </header>
  );
}

function ColIcon({ n }) {
  const w = 16, h = 11, gap = 1.5;
  const colW = (w - gap * (n - 1)) / n;
  return (
    <svg width={w} height={h} viewBox={`0 0 ${w} ${h}`} aria-hidden="true">
      {Array.from({length: n}).map((_, i) => (
        <rect key={i} x={i * (colW + gap)} y={0} width={colW} height={h} fill="currentColor" />
      ))}
    </svg>
  );
}

// ============ Colophon ============
function Colophon() {
  return (
    <footer className="colophon">
      <div>
        <h4>Veblen</h4>
        <div>For the rational consumer.</div>
        <div style={{marginTop: 6}}>Independent. No affiliate fees on graded items.</div>
      </div>
      <div>
        <h4>Sections</h4>
        <a href="#" onClick={e=>e.preventDefault()}>Browse all</a>
        <a href="#" onClick={e=>e.preventDefault()}>By grade</a>
        <a href="#" onClick={e=>e.preventDefault()}>By origin</a>
        <a href="#" onClick={e=>e.preventDefault()}>The Index</a>
      </div>
      <div>
        <h4>About</h4>
        <a href="#" onClick={e=>e.preventDefault()}>Methodology</a>
        <a href="#" onClick={e=>e.preventDefault()}>Editorial standards</a>
        <a href="#" onClick={e=>e.preventDefault()}>Why no synthetics</a>
        <a href="#" onClick={e=>e.preventDefault()}>Disclosures</a>
      </div>
      <div>
        <h4>Contact</h4>
        <a href="#" onClick={e=>e.preventDefault()}>desk@veblen.co</a>
        <a href="#" onClick={e=>e.preventDefault()}>Submit a brand</a>
        <a href="#" onClick={e=>e.preventDefault()}>Corrections</a>
        <div style={{marginTop: 12, fontSize: 9, color: "var(--ink-3)"}}>© MMXXVI Veblen Editorial Ltd.</div>
      </div>
    </footer>
  );
}

Object.assign(window, {
  GRADE_ORDER, GRADE_LETTER, GRADE_LABEL,
  GradeBadge, Sparkline, GarmentSwatch, DealCard,
  SizeRail, SizeSummary,
  Masthead, Colophon
});
