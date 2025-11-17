// TWDS Traffic Boom - Cloudflare Workers API
// This worker handles traffic reporting and statistics

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
};

export default {
  async fetch(request, env, ctx) {
    // Handle CORS preflight
    if (request.method === 'OPTIONS') {
      return new Response(null, { headers: CORS_HEADERS });
    }

    const url = new URL(request.url);
    const path = url.pathname;

    try {
      // Route handling
      if (path === '/api/report' && request.method === 'POST') {
        return await handleReport(request, env);
      } else if (path === '/api/stats' && request.method === 'GET') {
        return await handleGetStats(env);
      } else if (path === '/api/devices' && request.method === 'GET') {
        return await handleGetDevices(env);
      } else if (path === '/api/reset' && request.method === 'POST') {
        return await handleReset(env);
      } else {
        return new Response(JSON.stringify({ error: 'Not Found' }), {
          status: 404,
          headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
        });
      }
    } catch (error) {
      return new Response(JSON.stringify({ error: error.message }), {
        status: 500,
        headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
      });
    }
  },
};

// Handle incoming traffic reports from devices
async function handleReport(request, env) {
  const data = await request.json();
  const { device, totalRx, totalTx, rxSpeed, txSpeed, timestamp } = data;

  if (!device) {
    return new Response(JSON.stringify({ error: 'Device name required' }), {
      status: 400,
      headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
    });
  }

  // Store device data with TTL (auto-expire after 60 seconds of no updates)
  const deviceKey = `device:${device}`;
  const deviceData = {
    device,
    totalRx: totalRx || 0,
    totalTx: totalTx || 0,
    rxSpeed: rxSpeed || 0,
    txSpeed: txSpeed || 0,
    lastUpdate: timestamp || new Date().toISOString(),
  };

  await env.TRAFFIC_KV.put(deviceKey, JSON.stringify(deviceData), {
    expirationTtl: 60, // Device considered offline after 60 seconds
  });

  // Update global total (persistent)
  const globalStats = await getGlobalStats(env);

  // Get previous device stats to calculate delta
  const prevDeviceData = await env.TRAFFIC_KV.get(`prev:${device}`);
  let deltaRx = totalRx || 0;
  let deltaTx = totalTx || 0;

  if (prevDeviceData) {
    const prev = JSON.parse(prevDeviceData);
    deltaRx = Math.max(0, (totalRx || 0) - (prev.totalRx || 0));
    deltaTx = Math.max(0, (totalTx || 0) - (prev.totalTx || 0));
  }

  // Store current as previous for next delta calculation
  await env.TRAFFIC_KV.put(`prev:${device}`, JSON.stringify({
    totalRx: totalRx || 0,
    totalTx: totalTx || 0,
  }));

  // Update global totals
  globalStats.totalRx += deltaRx;
  globalStats.totalTx += deltaTx;
  globalStats.lastUpdate = new Date().toISOString();

  await env.TRAFFIC_KV.put('global:stats', JSON.stringify(globalStats));

  // Track device in active devices list
  const activeDevices = await getActiveDevicesList(env);
  if (!activeDevices.includes(device)) {
    activeDevices.push(device);
    await env.TRAFFIC_KV.put('global:devices', JSON.stringify(activeDevices));
  }

  return new Response(JSON.stringify({ success: true }), {
    headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
  });
}

// Get global statistics
async function handleGetStats(env) {
  const globalStats = await getGlobalStats(env);
  const activeDevices = await getActiveDevicesData(env);

  const response = {
    global: globalStats,
    devices: activeDevices,
    timestamp: new Date().toISOString(),
  };

  return new Response(JSON.stringify(response), {
    headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
  });
}

// Get list of devices
async function handleGetDevices(env) {
  const devices = await getActiveDevicesData(env);
  return new Response(JSON.stringify({ devices }), {
    headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
  });
}

// Reset all statistics (use with caution)
async function handleReset(env) {
  await env.TRAFFIC_KV.put('global:stats', JSON.stringify({
    totalRx: 0,
    totalTx: 0,
    lastUpdate: new Date().toISOString(),
  }));

  return new Response(JSON.stringify({ success: true, message: 'Statistics reset' }), {
    headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
  });
}

// Helper functions
async function getGlobalStats(env) {
  const data = await env.TRAFFIC_KV.get('global:stats');
  if (data) {
    return JSON.parse(data);
  }
  return {
    totalRx: 0,
    totalTx: 0,
    lastUpdate: new Date().toISOString(),
  };
}

async function getActiveDevicesList(env) {
  const data = await env.TRAFFIC_KV.get('global:devices');
  if (data) {
    return JSON.parse(data);
  }
  return [];
}

async function getActiveDevicesData(env) {
  const devicesList = await getActiveDevicesList(env);
  const activeDevices = [];

  for (const deviceName of devicesList) {
    const deviceData = await env.TRAFFIC_KV.get(`device:${deviceName}`);
    if (deviceData) {
      activeDevices.push(JSON.parse(deviceData));
    }
  }

  return activeDevices;
}
