const http = require('http');
const { readFileSync } = require('fs');
const { execFile } = require('child_process');
const { promisify } = require('util');
const path = require('path');

const exec = promisify(execFile);
const page = readFileSync(path.join(__dirname, 'index.html'));
const address = '127.0.0.1:8088';
const origin = `http://${address}`;
const context = process.env.CA2_KUBE_CONTEXT || 'ca2-resilience';
const workloads = new Map([
  ['dev', 'dev-service'],
  ['prod', 'checkout'],
]);

async function kubectl(profile, ...args) {
  const { stdout } = await exec('kubectl', [
    '--context', context, '--namespace', `ca2-${profile}`,
    '--request-timeout=8s', ...args,
  ], { timeout: 10000 });
  return JSON.parse(stdout);
}

function json(response, status, body) {
  response.writeHead(status, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
  response.end(JSON.stringify(body));
}

http.createServer(async (request, response) => {
  if (request.headers.host !== address) {
    return json(response, 403, { error: 'Open the panel at ' + origin });
  }
  if (request.method === 'GET' && request.url === '/') {
    response.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
    return response.end(page);
  }
  const match = /^\/api\/(dev|prod)(?:\/(up|down))?$/.exec(request.url);
  if (!match) return json(response, 404, { error: 'Unknown endpoint' });

  const [, profile, action] = match;
  const deployment = workloads.get(profile);
  try {
    if (!action && request.method === 'GET') {
      const { items } = await kubectl(profile, 'get', 'configmap/stress-control',
        `deployment/${deployment}`, `hpa/${deployment}`, '-o', 'json');
      const control = items.find(item => item.kind === 'ConfigMap');
      const workload = items.find(item => item.kind === 'Deployment');
      const autoscaler = items.find(item => item.kind === 'HorizontalPodAutoscaler');
      const metric = autoscaler.status?.currentMetrics?.find(item => item.type === 'ContainerResource');
      return json(response, 200, {
        until: Number(control.data.until),
        ready: workload.status?.readyReplicas ?? 0,
        desired: workload.spec.replicas,
        cpu: metric?.containerResource?.current?.averageUtilization ?? null,
      });
    }
    if (action && request.method === 'POST') {
      if (request.headers.origin !== origin) {
        return json(response, 403, { error: 'Request must come from the local panel' });
      }
      const until = action === 'up' ? Math.floor(Date.now() / 1000) + 600 : 0;
      await kubectl(profile, 'patch', 'configmap', 'stress-control', '--type=merge',
        '-p', JSON.stringify({ data: { until: String(until) } }), '-o', 'json');
      return json(response, 200, { until });
    }
    return json(response, 405, { error: 'Method not allowed' });
  } catch (error) {
    return json(response, 502, { error: error.stderr?.trim() || error.message });
  }
}).listen(8088, '127.0.0.1', () => console.log(`CA2 scaling panel: ${origin} (${context})`));
