// Veblen — page screens
const { useState: uS, useMemo: uM, useEffect: uE } = React;

// ============ BROWSE ============
function BrowseScreen({ onOpen, savedSet, onToggleSave, voice }) {
  const [filters, setFilters] = uS({
    category: "All categories",
    grade: "All grades",
    origin: "All origins",
    natural: "Any composition",
    discount: "≥50%",
  });
  const [chips, setChips] = uS([
    { k: "discount", v: "Discount ≥ 50%" },
    { k: "natural", v: "Natural fiber ≥ 80%" },
    { k: "grade", v: "Grade ≥ Good" },
  ]);
  const removeChip = (k) => setChips(chips.filter(c => c.k !== k));

  const items = window.VEBLEN_DATA.items;

  return (
    <div className="page">
      {/* Filter bar */}
      <div className="filter-bar">
        <div className="filter search">
          <input placeholder="Search by brand, fabric, country, construction…" />
        </div>
        {[
          ["category", "Category", filters.category],
          ["grade", "Grade", filters.grade],
          ["origin", "Origin", filters.origin],
          ["natural", "Composition", filters.natural],
          ["discount", "Discount", filters.discount],
        ].map(([k, lbl, v]) => (
          <div key={k} className="filter">
            <div className="lbl">{lbl}</div>
            <div className="val">{v}</div>
            <div className="car">▾</div>
          </div>
        ))}
      </div>

      {/* Active chips */}
      <div className="chips">
        {chips.map(c => (
          <span key={c.k} className="chip" onClick={() => removeChip(c.k)}>
            {c.v} <span className="x">×</span>
          </span>
        ))}
        <span style={{fontFamily:"var(--mono)", fontSize:10, color:"var(--ink-3)", letterSpacing:"0.08em", textTransform:"uppercase", alignSelf:"center", marginLeft:8}}>
          showing 312 of 1,847 listings · sorted by grade, then by % off retail
        </span>
      </div>

      {/* Grid */}
      <div className="deal-grid">
        {items.map(item => (
          <DealCard key={item.id} item={item} onOpen={onOpen} />
        ))}
      </div>

      <Colophon />
    </div>
  );
}

// ============ PRODUCT DETAIL ============
function ProductScreen({ item, onBack, onOpen, voice, savedSet, onToggleSave }) {
  const saved = savedSet.has(item.id);
  const others = window.VEBLEN_DATA.items.filter(i => i.id !== item.id).slice(0, 4);
  const firstAvail = item.sizes && (item.sizes.find(s => s[1] === "in") || item.sizes.find(s => s[1] === "low"));
  const [pickedSize, setPickedSize] = React.useState(firstAvail ? firstAvail[0] : null);
  React.useEffect(() => {
    const fa = item.sizes && (item.sizes.find(s => s[1] === "in") || item.sizes.find(s => s[1] === "low"));
    setPickedSize(fa ? fa[0] : null);
  }, [item.id]);
  const sizeKindLabel = ({alpha:"Size", neck:"Collar", waist:"Waist", us:"US Men's", one:"Size"})[item.sizeKind] || "Size";

  return (
    <div className="page">
      <div style={{padding: "16px 0", fontFamily:"var(--mono)", fontSize: 10, letterSpacing:"0.08em", textTransform:"uppercase", color:"var(--ink-2)"}}>
        <a href="#" onClick={e=>{e.preventDefault(); onBack();}} className="link">Browse</a>
        <span> / </span>
        <span>{item.category}</span>
        <span> / </span>
        <span style={{color:"var(--ink)"}}>{item.brand}</span>
      </div>

      {/* Hero */}
      <div style={{display:"grid", gridTemplateColumns:"1.2fr 1fr", gap: 0, borderTop:"2px solid var(--ink)", borderBottom: "1px solid var(--ink)"}}>
        <div style={{borderRight: "1px solid var(--rule-2)", aspectRatio:"4/5", background:"var(--paper-3)", position:"relative"}}>
          <GarmentSwatch id={item.id} category={item.category} />
          {item.flag && (
            <div className="deal-flag" style={{top: 24, left: 24, bottom: "auto", fontSize: 11}}>⚠ {item.flag}</div>
          )}
        </div>
        <div style={{padding: 32, display:"flex", flexDirection:"column"}}>
          <h1 style={{fontFamily:"var(--sans)", fontSize: 32, fontWeight: 600, lineHeight: 1.1, margin: "8px 0 16px", letterSpacing:"-0.02em"}}>
            {item.name}
          </h1>

          <div style={{margin: "8px 0 20px"}}>
            <GradeBadge grade={item.grade} large suffix="price for value" />
          </div>

          <hr className="hr-thin" />
          <div style={{display:"flex", alignItems:"baseline", gap: 14, padding: "12px 0"}}>
            <div style={{fontFamily:"var(--mono)", fontSize: 36, fontWeight: 600, lineHeight: 1}}>${item.price}</div>
            <div style={{fontFamily:"var(--mono)", fontSize: 14, textDecoration:"line-through", color:"var(--ink-3)"}}>${item.was}</div>
            <div className="deal-discount" style={{fontSize: 11}}>−{item.discount}%</div>
            <div style={{flex: 1}} />
            <div style={{fontFamily:"var(--mono)", fontSize: 10, color: "var(--ink-3)", textAlign: "right", textTransform:"uppercase", letterSpacing:"0.08em"}}>
              Sold at<br/>
              <b style={{color:"var(--ink)", letterSpacing: 0, textTransform:"none"}}>{item.retailer}</b>
            </div>
          </div>
          <hr className="hr-thin" />

          <div style={{padding: "14px 0", borderBottom: "1px solid var(--rule-2)"}}>
            <div style={{display:"flex", justifyContent:"space-between", alignItems:"baseline", marginBottom: 8}}>
              <div className="label">{sizeKindLabel}{pickedSize ? <span style={{color:"var(--ink)", textTransform:"none", letterSpacing:0, fontWeight: 600, marginLeft: 8}}>{pickedSize}</span> : null}</div>
              <SizeSummary sizes={item.sizes} />
            </div>
            <SizeRail sizes={item.sizes} kind={item.sizeKind} large picked={pickedSize} onPick={setPickedSize} />
          </div>

          <div style={{flex: 1, padding: "16px 0"}}>
            <div className="label" style={{marginBottom: 10}}>Specifications</div>
            <table className="ledger ledger-tight">
              <tbody>
                <tr><td style={{width: 120, color:"var(--ink-3)"}}>Material</td><td><b>{item.material}</b></td></tr>
                <tr><td style={{color:"var(--ink-3)"}}>Natural fiber</td><td><b className="tnum">{item.naturalPct}%</b></td></tr>
                <tr><td style={{color:"var(--ink-3)"}}>Origin</td><td><b>{item.origin}</b></td></tr>
                <tr><td style={{color:"var(--ink-3)"}}>Construction</td><td><b>{item.construction}</b></td></tr>
              </tbody>
            </table>
          </div>

          <div style={{display:"flex", gap: 8, marginTop: 16}}>
            <button className="btn primary" style={{flex: 1}}>Visit retailer →</button>
            <button className="btn" onClick={() => onToggleSave(item.id)}>
              {saved ? "★ Saved" : "☆ Save"}
            </button>
            <button className="btn">⌥ Set alert</button>
          </div>
          <div style={{fontFamily:"var(--mono)", fontSize: 9, color:"var(--ink-3)", marginTop: 10, letterSpacing:"0.04em"}}>
            Veblen receives no commission on this listing. Pricing pulled 12 minutes ago.
          </div>
        </div>
      </div>

      {/* Related */}
      <div className="section-rule">
        <h2>Comparable items</h2>
        <span className="meta">Same category, similar grade</span>
      </div>
      <div className="deal-grid">
        {others.map(o => <DealCard key={o.id} item={o} onOpen={onOpen} />)}
      </div>

      <Colophon />
    </div>
  );
}

// ============ METHODOLOGY ============
function MethodologyScreen() {
  return (
    <div className="page">
      <div style={{padding:"48px 0 32px", borderBottom: "2px solid var(--ink)", textAlign:"center"}}>
        <div className="label" style={{marginBottom: 8}}>The Method · Edition 3.2 · Effective 1 Mar 2026</div>
        <h1 style={{fontFamily:"var(--sans)", fontSize: 64, fontWeight: 600, margin: "8px 0", letterSpacing:"-0.03em", lineHeight: 1.0}}>
          How we grade.
        </h1>
        <div style={{fontFamily:"var(--sans)", fontSize: 18, fontWeight: 400, color: "var(--ink-2)", maxWidth: 640, margin: "16px auto 0", lineHeight: 1.45}}>
          A garment is graded against itself, not against fashion.
          The price is incidental to the question of what the thing actually is.
        </div>
      </div>

      <div style={{display:"grid", gridTemplateColumns: "240px 1fr 280px", gap: 40, marginTop: 40}}>
        <aside style={{fontFamily:"var(--mono)", fontSize: 11, color:"var(--ink-2)", borderRight: "1px solid var(--rule-2)", paddingRight: 20}}>
          <div className="label" style={{marginBottom: 8}}>Contents</div>
          {[
            "I. The premise",
            "II. The four factors",
            "III. The grade scale",
            "IV. On synthetics",
            "V. Editorial independence",
            "VI. Corrections & disputes",
          ].map(s => <div key={s} style={{padding:"4px 0", borderBottom: "1px dashed var(--rule-2)"}}>{s}</div>)}
        </aside>

        <article style={{fontFamily:"var(--sans)", fontSize: 15, lineHeight: 1.65, color:"var(--ink)", maxWidth: 640, letterSpacing:"-0.005em"}}>
          <h2 style={{fontFamily:"var(--sans)", fontWeight: 600, fontSize: 22, margin:"0 0 8px", letterSpacing:"-0.02em"}}>I. The premise</h2>
          <p style={{margin:"0 0 16px"}}>
            Most clothing sold at any meaningful price contains markup unrelated to quality: brand rent,
            marketing amortization, the cost of a flagship store you will never visit. Veblen exists to
            isolate the part of the price that buys you something — material, construction, country of
            manufacture, and time — from the part that buys you nothing.
          </p>
          <p style={{margin:"0 0 16px"}}>
            We list only items discounted at fifty percent or more from a documented retail price held for
            at least sixty days. Below that threshold, the discount is decorative.
          </p>

          <h2 style={{fontFamily:"var(--sans)", fontWeight: 600, fontSize: 22, margin:"32px 0 8px", letterSpacing:"-0.02em"}}>II. The four factors</h2>
          <p style={{margin:"0 0 16px"}}>
            Each listing is scored against a baseline of fifty and adjusted by four factors,
            weighted by category. A goodyear-welted shoe is judged on different terms than a t-shirt;
            the relative weights are published per-category in the appendix.
          </p>
          <table className="ledger" style={{margin:"16px 0"}}>
            <thead><tr><th>Factor</th><th>Range</th><th>What we measure</th></tr></thead>
            <tbody>
              <tr><td><b>Material</b></td><td>−24 to +24</td><td>Fiber composition, weight, weave, source</td></tr>
              <tr><td><b>Origin</b></td><td>−6 to +18</td><td>Country and region; documented mill or maker</td></tr>
              <tr><td><b>Construction</b></td><td>−12 to +24</td><td>Stitching, lining, hardware, joinery</td></tr>
              <tr><td><b>Price history</b></td><td>+0 to +14</td><td>Distance from price floor, sale frequency</td></tr>
            </tbody>
          </table>

          <h2 style={{fontFamily:"var(--sans)", fontWeight: 600, fontSize: 22, margin:"32px 0 8px", letterSpacing:"-0.02em"}}>III. The grade scale</h2>
          <div style={{display:"grid", gridTemplateColumns:"repeat(5, 1fr)", gap: 8, margin: "16px 0"}}>
            {GRADE_ORDER.map(g => (
              <div key={g} style={{textAlign:"center"}}>
                <GradeBadge grade={g} />
                <div style={{fontFamily:"var(--mono)", fontSize: 10, color:"var(--ink-3)", marginTop: 8, letterSpacing:"0.04em"}}>
                  {  {excellent:"Top tier",great:"Recommended",good:"Acceptable",fair:"Caveats apply",poor:"Avoid"}[g] }
                </div>
              </div>
            ))}
          </div>
          <p style={{margin:"16px 0"}}>
            <i>Excellent</i> grades are not generous. In any given week we list more <i>Fair</i> items than
            anything else, because the world produces more fair clothing than any other kind.
          </p>

          <h2 style={{fontFamily:"var(--sans)", fontWeight: 600, fontSize: 22, margin:"32px 0 8px", letterSpacing:"-0.02em"}}>IV. On synthetics</h2>
          <p className="pullquote" style={{fontSize: 26, lineHeight: 1.3, margin:"16px 0"}}>
            We have an editorial bias against synthetic fibers.
            We will not pretend otherwise.
          </p>
          <p style={{margin:"0 0 16px"}}>
            Polyester, nylon, acrylic, and elastane do not age. They abrade, pill, retain odor,
            and shed microplastics into the laundry. They cannot be repaired by any process other
            than replacement. They are excellent for tents and rope. They are poor for clothes
            you intend to keep.
          </p>
          <p style={{margin:"0 0 16px"}}>
            A garment with more than fifteen percent synthetic content cannot grade higher than
            <i> Good</i>, regardless of other factors. We flag synthetic content prominently. We
            do not believe "recycled polyester" is an environmental virtue; it is a manufacturing
            input, and the resulting garment still ends up as plastic.
          </p>

          <h2 style={{fontFamily:"var(--sans)", fontWeight: 600, fontSize: 22, margin:"32px 0 8px", letterSpacing:"-0.02em"}}>V. Editorial independence</h2>
          <p style={{margin:"0 0 16px"}}>
            Veblen does not accept advertising, sponsored placements, or affiliate commissions on
            graded items. We pay the retail price for sample inspection. Brands cannot pay to be
            listed and cannot pay to be removed.
          </p>
        </article>

        <aside style={{fontFamily:"var(--mono)", fontSize: 11, color:"var(--ink-2)"}}>
          <div className="label" style={{marginBottom: 8}}>In the margins</div>
          <div style={{padding: 12, border:"1px solid var(--rule-2)", marginBottom: 12, lineHeight: 1.5}}>
            <b style={{color:"var(--ink)"}}>Method version</b><br/>
            v3.2 — published 1 Mar 2026. Changelog available on request.
          </div>
          <div style={{padding: 12, border:"1px solid var(--rule-2)", marginBottom: 12, lineHeight: 1.5}}>
            <b style={{color:"var(--ink)"}}>Synthetic ceiling</b><br/>
            Items above 15% synthetic content cap at the <b>Good</b> grade.
          </div>
          <div style={{padding: 12, border:"1px solid var(--rule-2)", lineHeight: 1.5}}>
            <b style={{color:"var(--ink)"}}>Disclosure</b><br/>
            We hold no equity in any listed brand. Editor & founder: J. Marcus Halloran.
          </div>
        </aside>
      </div>

      <Colophon />
    </div>
  );
}

// ============ SAVED & ALERTS ============
function SavedScreen({ savedSet, onToggleSave, onOpen }) {
  const [tab, setTab] = uS("saved");
  const items = window.VEBLEN_DATA.items;
  const saved = items.filter(i => savedSet.has(i.id));
  const alerts = window.VEBLEN_DATA.alerts;

  return (
    <div className="page">
      <div style={{padding: "32px 0 16px"}}>
        <div className="label">Your File</div>
        <h1 style={{fontFamily:"var(--sans)", fontSize: 40, fontWeight: 600, margin: "4px 0", letterSpacing: "-0.025em"}}>
          Saved & Alerts
        </h1>
      </div>

      <div style={{display:"flex", gap: 0, borderBottom:"1px solid var(--ink)", marginBottom: 16}}>
        {[
          ["saved", `Saved items · ${saved.length}`],
          ["alerts", `Alerts · ${alerts.length}`],
          ["history", "Watch history"],
        ].map(([k, lbl]) => (
          <button key={k} className="btn"
            style={{
              border: 0, borderRight: "1px solid var(--rule-2)",
              background: tab === k ? "var(--ink)" : "transparent",
              color: tab === k ? "var(--paper)" : "var(--ink-2)",
              padding: "10px 18px",
            }}
            onClick={() => setTab(k)}>
            {lbl}
          </button>
        ))}
      </div>

      {tab === "saved" && (
        <>
          <div style={{display:"flex", justifyContent:"space-between", alignItems:"center", marginBottom: 16, fontFamily:"var(--mono)", fontSize: 11, color:"var(--ink-2)", textTransform:"uppercase", letterSpacing:"0.06em"}}>
            <span>Saved items, sorted by recent price change</span>
            <span><b style={{color:"var(--ink)"}}>3</b> moved down · <b style={{color:"var(--grade-poor)"}}>1</b> went out of stock</span>
          </div>
          <table className="ledger">
            <thead>
              <tr>
                <th style={{width: 60}}></th>
                <th>Item</th>
                <th>Grade</th>
                <th>Sizes</th>
                <th style={{textAlign:"right"}}>Price</th>
                <th style={{textAlign:"right"}}>Was</th>
                <th style={{textAlign:"right"}}>Δ since saved</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              {saved.map(item => {
                const savedAt = item.history[Math.max(0, item.history.length - 6)];
                const change = ((item.price - savedAt) / savedAt * 100).toFixed(1);
                const down = item.price < savedAt;
                return (
                  <tr key={item.id} style={{cursor:"pointer"}} onClick={() => onOpen(item)}>
                    <td>
                      <div style={{width: 44, height: 56, background:"var(--paper-3)"}}>
                        <GarmentSwatch id={item.id} category={item.category} />
                      </div>
                    </td>
                    <td>
                      <b>{item.name}</b><br/>
                      <span style={{color:"var(--ink-3)", fontSize: 10, letterSpacing:"0.06em", textTransform:"uppercase"}}>
                        {item.brand} · {item.origin}
                      </span>
                    </td>
                    <td><GradeBadge grade={item.grade} /></td>
                    <td><SizeSummary sizes={item.sizes} /></td>
                    <td style={{textAlign:"right"}}><b className="tnum">${item.price}</b></td>
                    <td style={{textAlign:"right", color:"var(--ink-3)", textDecoration:"line-through"}}><span className="tnum">${item.was}</span></td>
                    <td style={{textAlign:"right", color: down ? "var(--grade-excellent)" : "var(--grade-poor)", fontWeight: 600}} className="tnum">
                      {down ? "↓" : "↑"} {Math.abs(change)}%
                    </td>
                    <td onClick={e => {e.stopPropagation(); onToggleSave(item.id);}} style={{cursor:"pointer", color:"var(--ink-3)", fontSize: 10}}>remove ×</td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </>
      )}

      {tab === "alerts" && (
        <>
          <div style={{display:"flex", gap: 12, marginBottom: 16}}>
            <div className="filter search" style={{flex: 1, border:"1px solid var(--rule-2)"}}>
              <input placeholder="Describe a new alert in plain English… e.g. 'Italian shoes, ≥A grade, under $300'" />
            </div>
            <button className="btn primary">+ Create alert</button>
          </div>

          <table className="ledger">
            <thead>
              <tr>
                <th>Query</th>
                <th style={{textAlign:"right"}}>Matches</th>
                <th>Last fired</th>
                <th>Channel</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              {alerts.map(a => (
                <tr key={a.id}>
                  <td><b>{a.query}</b></td>
                  <td style={{textAlign:"right"}} className="tnum"><b>{a.matches}</b></td>
                  <td style={{color:"var(--ink-2)"}}>{a.last}</td>
                  <td style={{color:"var(--ink-2)"}}>Email · weekly digest</td>
                  <td style={{color:"var(--ink-3)", fontSize: 10}}>edit · pause · delete</td>
                </tr>
              ))}
            </tbody>
          </table>

          {/* Email preview */}
          <div className="section-rule">
            <h2>Sample digest</h2>
            <span className="meta">Friday morning · ~6 items</span>
          </div>
          <div style={{maxWidth: 580, border: "1px solid var(--ink)", padding: 24, background: "var(--paper)"}}>
            <div style={{borderBottom: "1px solid var(--rule-2)", paddingBottom: 12, marginBottom: 16, fontFamily:"var(--mono)", fontSize: 10, color:"var(--ink-3)", letterSpacing:"0.06em", textTransform:"uppercase"}}>
              <div>From: desk@veblen.co</div>
              <div>Subject: <b style={{color:"var(--ink)"}}>This week, six items worth your attention.</b></div>
            </div>
            <div style={{fontFamily:"var(--sans)", fontSize: 24, fontWeight: 600, letterSpacing:"-0.02em", marginBottom: 12}}>Veblen, weekly.</div>
            <div style={{fontFamily:"var(--sans)", fontSize: 14, lineHeight: 1.55, color:"var(--ink-2)", marginBottom: 16}}>
              Three Excellent listings cleared the threshold this week — including a Loro Piana topcoat at 57% off and a pair of goodyear-welted loafers from Northampton. Full notes below.
            </div>
            <ol style={{paddingLeft: 16, fontFamily:"var(--sans)", fontSize: 13, lineHeight: 1.6, color:"var(--ink)"}}>
              <li>Harringate Storm-System Topcoat — <b>Excellent · $1,240</b></li>
              <li>Kellner & Roe Goodyear Loafer — <b>Excellent · $285</b></li>
              <li>A.B. Knit Co. Shetland Cardigan — <b>Excellent · $142</b></li>
              <li>Travers Fresco Trouser — <b>Great · $215</b></li>
              <li>Caldwell & Sons OCBD — <b>Great · $88</b></li>
              <li>Velten Lambswool Roll-Neck — <b>Great · $84</b></li>
            </ol>
          </div>
        </>
      )}

      {tab === "history" && (
        <div style={{padding: 60, textAlign:"center", fontFamily:"var(--sans)", fontSize: 16, color:"var(--ink-3)"}}>
          Watch history — items you opened but did not save.
          <div style={{fontFamily:"var(--mono)", fontSize: 11, marginTop: 12, color: "var(--ink-3)", letterSpacing: "0.06em", textTransform:"uppercase"}}>Coming soon</div>
        </div>
      )}

      <Colophon />
    </div>
  );
}

Object.assign(window, { BrowseScreen, ProductScreen, MethodologyScreen, SavedScreen });
