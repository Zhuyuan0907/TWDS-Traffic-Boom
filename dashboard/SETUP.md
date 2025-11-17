# TWDS Traffic Boom - Dashboard Setup Guide

This guide will help you set up the traffic monitoring dashboard using Cloudflare Workers and Pages.

## Overview

The system consists of three parts:
1. **PowerShell Script** - Runs on Windows to download files and report traffic
2. **Cloudflare Workers API** - Backend that receives and stores traffic data
3. **Dashboard Web Page** - Frontend that displays real-time statistics

## Prerequisites

- [Node.js](https://nodejs.org/) (v16 or later)
- [Wrangler CLI](https://developers.cloudflare.com/workers/wrangler/install-and-update/)
- A Cloudflare account (free tier works)

## Step 1: Install Wrangler CLI

```bash
npm install -g wrangler
```

## Step 2: Login to Cloudflare

```bash
wrangler login
```

This will open a browser window to authenticate.

## Step 3: Create KV Namespace

```bash
cd dashboard
wrangler kv:namespace create "TRAFFIC_KV"
```

This will output something like:
```
🌀 Creating namespace with title "twds-traffic-api-TRAFFIC_KV"
✨ Success!
Add the following to your configuration file in your kv_namespaces array:
{ binding = "TRAFFIC_KV", id = "YOUR_ACTUAL_ID_HERE" }
```

**Copy the ID** and update `wrangler.toml`:
```toml
[[kv_namespaces]]
binding = "TRAFFIC_KV"
id = "YOUR_ACTUAL_ID_HERE"  # Replace with the ID from above
```

## Step 4: Deploy the Worker

```bash
wrangler deploy
```

This will output your Worker URL, something like:
```
https://twds-traffic-api.YOUR_SUBDOMAIN.workers.dev
```

**Save this URL** - you'll need it for the dashboard and PowerShell script.

## Step 5: Deploy Dashboard to Cloudflare Pages

### Option A: Using Wrangler

```bash
wrangler pages deploy . --project-name=twds-dashboard
```

### Option B: Using Cloudflare Dashboard

1. Go to [Cloudflare Dashboard](https://dash.cloudflare.com/)
2. Click "Pages" in the sidebar
3. Click "Create a project" → "Direct Upload"
4. Upload the `index.html` file
5. Deploy

### Option C: Using Git Integration

1. Push the `dashboard` folder to a GitHub repository
2. In Cloudflare Pages, connect to your GitHub repo
3. Set the build output directory to the folder containing `index.html`
4. Deploy

## Step 6: Configure the Dashboard

1. Open your Cloudflare Pages URL (e.g., `https://twds-dashboard.pages.dev`)
2. Enter your Worker API URL in the configuration box
3. Click "Save"

## Step 7: Configure PowerShell Script

Edit `Start-TWDS-WithAPI.bat`:

```batch
set "API_URL=https://twds-traffic-api.YOUR_SUBDOMAIN.workers.dev"
```

Or run directly:
```powershell
powershell -ExecutionPolicy Bypass -File "Traffic-Boom-Windows-Version.ps1" -ApiEndpoint "https://twds-traffic-api.YOUR_SUBDOMAIN.workers.dev"
```

## Usage

### Start Traffic Generation

**Method 1: Double-click the batch file**
- `Start-TWDS.bat` - Basic usage (no API reporting)
- `Start-TWDS-WithAPI.bat` - With API reporting (edit API URL first)

**Method 2: PowerShell command**
```powershell
# Basic usage (real download, no API)
.\Traffic-Boom-Windows-Version.ps1

# With API reporting
.\Traffic-Boom-Windows-Version.ps1 -ApiEndpoint "https://your-api.workers.dev"

# Custom device name
.\Traffic-Boom-Windows-Version.ps1 -ApiEndpoint "https://your-api.workers.dev" -DeviceName "MyPC"

# Multiple parallel downloads
.\Traffic-Boom-Windows-Version.ps1 -ParallelDownloads 5 -ApiEndpoint "https://your-api.workers.dev"

# Simulate mode (no actual network traffic)
.\Traffic-Boom-Windows-Version.ps1 -SimulateOnly
```

### Monitor Traffic

1. Open your dashboard URL
2. View real-time statistics
3. See all connected devices
4. Monitor download/upload speeds

## API Endpoints

- `POST /api/report` - Report traffic from device
- `GET /api/stats` - Get all statistics
- `GET /api/devices` - Get device list
- `POST /api/reset` - Reset all statistics (use with caution)

## Important Notes

1. **Data Persistence**: Total traffic statistics are stored in Cloudflare KV and persist even after closing scripts
2. **Device Timeout**: Devices are considered offline after 60 seconds of no updates
3. **Free Tier Limits**: Cloudflare Workers free tier has limits (100k requests/day, 10ms CPU time)
4. **Privacy**: All data is stored in your own Cloudflare account

## Troubleshooting

### PowerShell script won't run
Use the batch file or run with `-ExecutionPolicy Bypass`

### No data in dashboard
1. Check API URL is correct
2. Check browser console for errors
3. Verify Worker is deployed successfully
4. Test API directly: `curl https://your-api.workers.dev/api/stats`

### Worker deployment fails
1. Ensure KV namespace ID is correct in `wrangler.toml`
2. Check you're logged in: `wrangler whoami`
3. Try `wrangler deploy --dry-run` to see errors

## Cost Estimate (Cloudflare Free Tier)

- Workers: 100,000 requests/day free
- KV: 100,000 reads/day, 1,000 writes/day free
- Pages: Unlimited static hosting

With 5-second reporting intervals, one device uses ~17,280 requests/day, so you can support 5-6 devices on the free tier.

## Security Considerations

- The API is open by default (no authentication)
- Anyone with your API URL can send fake data
- Consider adding authentication for production use
- Reset button can clear all historical data
