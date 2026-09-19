import { useDemoData } from '@/data/useDemoData';
import { MlNotice, MlRouteSummary, MlTopAlertsPanel } from '@/components/MlRisk';
import { fetchRoutesSummary, useMlQuery } from '@/lib/ml';
import { profileService } from '@/lib/profileService';
import { SeverityBadge } from '@/components/StatusBadge';

export default function AIInsights() {
  const { aiInsights } = useDemoData();
  const routes = useMlQuery(fetchRoutesSummary);
  // The database enforces this too; the button only appears where it can succeed.
  const role = profileService.getCurrentRole();
  const canPromote = role === 'control' || role === 'district';

  return (
    <div className="space-y-6 max-w-screen-2xl">
      <div className="flex items-start justify-between">
        <div>
          <div className="flex items-center gap-2">
            <span style={{ color: '#D7A73A' }}>✦</span>
            <h1 className="font-semibold text-2xl" style={{ color: '#17212B' }}>AI Insights</h1>
          </div>
          <p className="text-sm mt-0.5" style={{ color: '#5A6670' }}>
            AI-generated predictions and recommendations
          </p>
        </div>
        <div className="text-xs px-3 py-1.5 rounded border" style={{ background: '#FEF8E6', borderColor: '#F5DFA8', color: '#C4861A' }}>
          ✦ AI-generated estimates · Confidence varies
        </div>
      </div>

      {/* Disclaimer */}
      <div className="rounded-xl border p-3 flex items-center gap-2"
        style={{ background: 'rgba(238,228,210,0.88)', borderColor: 'rgba(180,162,136,0.55)' }}>
        <span className="text-lg" style={{ color: '#D7A73A' }}>✦</span>
        <p className="text-xs" style={{ color: '#5A6670' }}>
          <strong>Road Disruption Risk</strong> is the NER model's daily ranking of every corridor road segment by
          rainfall-triggered disruption risk. The other panels are demo data. All of it is advisory, not confirmed
          fact — District Officer discretion required.
        </p>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">

        {/* Road disruption risk — live model output (sih-ml), kept apart from demo estimates */}
        <div className="rounded-xl border shadow-sm lg:col-span-2" style={{ background: 'rgba(250,247,240,0.82)', borderColor: 'rgba(180,162,136,0.55)' }}>
          <div className="px-4 py-3 border-b" style={{ borderColor: 'rgba(180,162,136,0.55)', background: 'rgba(238,228,210,0.88)' }}>
            <h2 className="font-semibold text-base" style={{ color: '#17212B' }}>Road Disruption Risk</h2>
            <p className="text-xs" style={{ color: '#8A9098' }}>Model output · rainfall-triggered landslide and flood risk per road segment</p>
          </div>
          <div className="p-4 grid grid-cols-1 xl:grid-cols-2 gap-6">
            <section className="space-y-2">
              <h3 className="text-sm font-semibold" style={{ color: '#17212B' }}>Highest-risk segments today</h3>
              <MlTopAlertsPanel canPromote={canPromote} />
            </section>
            <section className="space-y-2">
              <h3 className="text-sm font-semibold" style={{ color: '#17212B' }}>Risk on planned routes</h3>
              <MlNotice signedOut={routes.signedOut} error={routes.error} />
              {routes.loading && !routes.data && !routes.signedOut && (
                <div className="text-xs" style={{ color: '#8A9098' }}>Loading routes…</div>
              )}
              <div className="space-y-3">
                {(routes.data?.routes ?? []).map((r) => (
                  <div key={r.route_id} className="rounded-lg border p-3" style={{ borderColor: 'rgba(180,162,136,0.55)' }}>
                    <div className="font-semibold text-sm mb-2" style={{ color: '#17212B' }}>{r.name}</div>
                    <MlRouteSummary meta={routes.data} summary={r.summary} coverage={r.coverage_fraction} lengthM={r.route_length_m} />
                  </div>
                ))}
              </div>
            </section>
          </div>
        </div>

        {/* Logistics Predictions */}
        <div className="rounded-xl border shadow-sm" style={{ background: 'rgba(250,247,240,0.82)', borderColor: 'rgba(180,162,136,0.55)' }}>
          <div className="px-4 py-3 border-b" style={{ borderColor: 'rgba(180,162,136,0.55)', background: 'rgba(238,228,210,0.88)' }}>
            <h2 className="font-semibold text-base" style={{ color: '#17212B' }}>Logistics Delay Predictions</h2>
            <p className="text-xs" style={{ color: '#8A9098' }}>Demo data · not model output</p>
          </div>
          <div className="p-4 space-y-3">
            <div className="rounded p-3 border" style={{ background: '#FEF8E6', borderColor: '#F5DFA8' }}>
              <div className="flex items-center gap-1.5 mb-1">
                <span style={{ color: '#D7A73A' }}>✦</span>
                <span className="text-sm font-semibold" style={{ color: '#17212B' }}>
                  {aiInsights.logisticsPredictions.reduce((a, b) => a + b.convoys, 0)} logistics routes may experience delays
                </span>
              </div>
              <p className="text-xs" style={{ color: '#8A9098' }}>Based on current incident data and weather forecasts</p>
            </div>
            {aiInsights.logisticsPredictions.map(p => (
              <div key={p.route} className="rounded-lg border p-3" style={{ borderColor: 'rgba(180,162,136,0.55)' }}>
                <div className="flex items-center justify-between mb-1">
                  <span className="font-semibold text-sm" style={{ color: '#17212B' }}>Route {p.route}</span>
                  <span className="font-semibold text-xs" style={{ color: p.probability > 80 ? '#BE2424' : '#C4861A' }}>
                    {p.probability}% probability
                  </span>
                </div>
                <div className="grid grid-cols-2 text-xs gap-1">
                  <div style={{ color: '#8A9098' }}>Affected convoys: <span style={{ color: '#17212B' }} className="font-medium">{p.convoys}</span></div>
                  <div style={{ color: '#8A9098' }}>Est. delay: <span style={{ color: '#C25A1A' }} className="font-semibold">{p.estimatedDelay}</span></div>
                  <div className="col-span-2" style={{ color: '#8A9098' }}>Cause: <span style={{ color: '#17212B' }}>{p.cause}</span></div>
                </div>
              </div>
            ))}
          </div>
        </div>

        {/* Route Recommendations */}
        <div className="rounded-xl border shadow-sm" style={{ background: 'rgba(250,247,240,0.82)', borderColor: 'rgba(180,162,136,0.55)' }}>
          <div className="px-4 py-3 border-b" style={{ borderColor: 'rgba(180,162,136,0.55)', background: 'rgba(238,228,210,0.88)' }}>
            <h2 className="font-semibold text-base" style={{ color: '#17212B' }}>Route Recommendations</h2>
            <p className="text-xs" style={{ color: '#8A9098' }}>Demo data · not model output</p>
          </div>
          <div className="p-4 space-y-3">
            {aiInsights.routeRecommendations.map((rec, i) => (
              <div key={i} className="rounded-lg border p-3" style={{ background: '#EAF4EE', borderColor: '#A8D4B8' }}>
                <div className="flex items-start gap-2 mb-2">
                  <span style={{ color: '#2D6B4F', fontSize: 16 }}>✓</span>
                  <div>
                    <div className="text-sm font-semibold" style={{ color: '#17212B' }}>
                      {rec.from} → {rec.to}
                    </div>
                    <div className="text-xs" style={{ color: '#5A6670' }}>{rec.reason}</div>
                  </div>
                </div>
                <div className="grid grid-cols-2 text-xs gap-1">
                  <div style={{ color: '#8A9098' }}>Benefit: <span style={{ color: '#2D6B4F' }}>{rec.savings}</span></div>
                  <div style={{ color: '#8A9098' }}>Add. distance: <span style={{ color: '#17212B' }}>{rec.additionalDistance}</span></div>
                </div>
              </div>
            ))}
          </div>
        </div>

        {/* Resource Recommendations */}
        <div className="rounded-xl border shadow-sm" style={{ background: 'rgba(250,247,240,0.82)', borderColor: 'rgba(180,162,136,0.55)' }}>
          <div className="px-4 py-3 border-b" style={{ borderColor: 'rgba(180,162,136,0.55)', background: 'rgba(238,228,210,0.88)' }}>
            <h2 className="font-semibold text-base" style={{ color: '#17212B' }}>Resource Recommendations</h2>
            <p className="text-xs" style={{ color: '#8A9098' }}>Demo data · not model output</p>
          </div>
          <div className="p-4 space-y-3">
            {aiInsights.resourceRecommendations.map((rec, i) => (
              <div key={i} className="rounded-lg border p-3 flex gap-3" style={{ borderColor: 'rgba(180,162,136,0.55)' }}>
                <span className="text-lg flex-shrink-0" style={{ color: '#D7A73A' }}>✦</span>
                <div>
                  <p className="text-xs leading-relaxed" style={{ color: '#17212B' }}>{rec}</p>
                  <div className="flex gap-2 mt-2">
                    <button className="text-xs px-2 py-1 rounded border"
                      style={{ background: '#17324D', color: 'white', borderColor: '#17324D' }}>
                      Act on Recommendation
                    </button>
                    <button className="text-xs px-2 py-1 rounded border"
                      style={{ borderColor: 'rgba(180,162,136,0.55)', color: '#5A6670' }}>Dismiss</button>
                  </div>
                </div>
              </div>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
}
