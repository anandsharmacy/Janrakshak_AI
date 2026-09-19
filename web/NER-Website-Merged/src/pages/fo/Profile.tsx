import { useState, useEffect } from 'react';
import { Card, CardHeader, PageHeader, BORDER, SURFACE_2, NAVY, TEAL } from './ui';
import { profileService } from '@/lib/profileService';

export default function Profile() {
  const [profile, setProfile] = useState(() => {
    try {
      return profileService.getProfile();
    } catch (error) {
      console.error('Error loading profile in FO Profile:', error);
      // Return a safe fallback
      return {
        label: 'Field Officer',
        profileName: 'Field Officer',
        profileInitials: 'FO',
        officerId: 'UNKNOWN',
        department: 'Field Operations',
        region: 'Unknown District',
        phone: '',
        email: '',
        lastLogin: 'Unknown',
        status: 'Active',
      };
    }
  });

  // Subscribe to profile changes
  useEffect(() => {
    const unsubscribe = profileService.subscribe((updatedProfile) => {
      try {
        setProfile(updatedProfile);
      } catch (error) {
        console.error('Error updating profile in FO Profile:', error);
      }
    });
    return unsubscribe;
  }, []);

  const INFO = [
    ['Officer Name', profile.profileName],
    ['Officer ID', profile.officerId],
    ['Designation', profile.label],
    ['Assigned District', profile.region],
    ['Assigned Area', profile.region],
    ['Contact', `${profile.phone} · ${profile.email}`],
    ['Availability', profile.status],
    ['Last Synchronization', profile.lastLogin],
    ['Device / Connectivity', 'Android · Online (4G)'],
  ];

const SECTIONS = [
  { icon: '◬', title: 'Notification Preferences', sub: 'Alerts, task assignments and sync updates' },
  { icon: '⇩', title: 'Offline Data', sub: '2 reports queued · syncs automatically when online' },
  { icon: '⚿', title: 'Security', sub: 'Password, device sessions and PIN lock' },
];

  return (
    <div className="space-y-6 max-w-4xl">
      <PageHeader title="Profile" sub="Field officer account and device settings" />

      <Card className="p-5">
        <div className="flex items-center gap-4 mb-5">
          <div className="w-16 h-16 rounded-full flex items-center justify-center text-xl font-bold" style={{ background: NAVY, color: 'white' }}>{profile.profileInitials}</div>
          <div>
            <div className="font-semibold text-lg" style={{ color: '#17212B' }}>{profile.profileName}</div>
            <div className="text-sm" style={{ color: '#5A6670' }}>{profile.label} · {profile.officerId}</div>
            <span className="inline-flex items-center gap-1.5 text-xs px-2 py-0.5 rounded border mt-1.5"
              style={{ background: '#EAF4EE', borderColor: '#A8D4B8', color: '#2D6B4F' }}>
              <span className="w-1.5 h-1.5 rounded-full bg-green-500 inline-block" /> {profile.status} · Online
            </span>
          </div>
        </div>
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-x-6">
          {INFO.map(([k, v]) => (
            <div key={k} className="flex justify-between py-2.5 border-b text-sm" style={{ borderColor: SURFACE_2 }}>
              <span className="text-xs font-medium" style={{ color: '#8A9098' }}>{k}</span>
              <span className="text-right" style={{ color: '#17212B' }}>{v}</span>
            </div>
          ))}
        </div>
      </Card>

      <Card>
        <CardHeader title="Settings" />
        <div className="divide-y" style={{ borderColor: SURFACE_2 }}>
          {SECTIONS.map(s => (
            <button key={s.title} className="w-full px-4 py-3 flex items-center gap-3 text-left transition-colors hover:bg-black/[0.02]" style={{ minHeight: 44 }}>
              <div className="w-9 h-9 rounded-lg flex items-center justify-center flex-shrink-0" style={{ background: SURFACE_2, color: NAVY }}>{s.icon}</div>
              <div className="flex-1">
                <div className="text-sm font-medium" style={{ color: '#17212B' }}>{s.title}</div>
                <div className="text-xs" style={{ color: '#8A9098' }}>{s.sub}</div>
              </div>
              <span style={{ color: '#8A9098' }}>›</span>
            </button>
          ))}
          <button className="w-full px-4 py-3 flex items-center gap-3 text-left transition-colors hover:bg-red-50" style={{ minHeight: 44 }}>
            <div className="w-9 h-9 rounded-lg flex items-center justify-center flex-shrink-0" style={{ background: '#FEE9E9', color: '#BE2424' }}>→</div>
            <span className="text-sm font-medium" style={{ color: '#BE2424' }}>Logout</span>
          </button>
        </div>
      </Card>
    </div>
  );
}
