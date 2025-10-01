// ═══════════════════════════════════════════════════════════════════
// COMPLETE FULL-STACK APPLICATION WITH MONITORING
// ═══════════════════════════════════════════════════════════════════
// This single file contains:
// - Express REST API Backend
// - React Frontend (served by Express)
// - MongoDB Integration
// - Health Checks & Metrics
// - Auto-scaling Ready
// - Production-grade Error Handling
// ═══════════════════════════════════════════════════════════════════

const express = require('express');
const mongoose = require('mongoose');
const cors = require('cors');
const path = require('path');

// ═══════════════════════════════════════════════════════════════════
// CONFIGURATION & ENVIRONMENT
// ═══════════════════════════════════════════════════════════════════

const CONFIG = {
  PORT: process.env.PORT || 3000,
  MONGODB_URI: process.env.MONGODB_URI || 'mongodb://localhost:27017/awesome-devops',
  NODE_ENV: process.env.NODE_ENV || 'development',
  APP_VERSION: '1.0.0',
  APP_NAME: 'Awesome DevOps Application'
};

// Metrics tracking for auto-scaling decisions
const METRICS = {
  requestCount: 0,
  errorCount: 0,
  startTime: Date.now(),
  healthChecks: 0,
  apiCalls: 0
};

// ═══════════════════════════════════════════════════════════════════
// MONGODB MODEL
// ═══════════════════════════════════════════════════════════════════

const ItemSchema = new mongoose.Schema({
  name: {
    type: String,
    required: true,
    trim: true,
    minlength: 3,
    maxlength: 100
  },
  description: {
    type: String,
    required: true,
    trim: true,
    maxlength: 500
  },
  status: {
    type: String,
    enum: ['active', 'inactive', 'pending'],
    default: 'active'
  },
  priority: {
    type: Number,
    default: 1,
    min: 1,
    max: 5
  },
  createdAt: {
    type: Date,
    default: Date.now
  },
  updatedAt: {
    type: Date,
    default: Date.now
  }
});

ItemSchema.pre('save', function(next) {
  this.updatedAt = Date.now();
  next();
});

const Item = mongoose.model('Item', ItemSchema);

// ═══════════════════════════════════════════════════════════════════
// EXPRESS APP INITIALIZATION
// ═══════════════════════════════════════════════════════════════════

const app = express();

// Middleware
app.use(cors());
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// Request tracking middleware
app.use((req, res, next) => {
  METRICS.requestCount++;
  const start = Date.now();
  
  res.on('finish', () => {
    const duration = Date.now() - start;
    console.log(`${req.method} ${req.path} - ${res.statusCode} - ${duration}ms`);
  });
  
  next();
});

// ═══════════════════════════════════════════════════════════════════
// HEALTH CHECK & METRICS ENDPOINTS (Critical for K8s)
// ═══════════════════════════════════════════════════════════════════

// Liveness probe - Is the app running?
app.get('/health', (req, res) => {
  METRICS.healthChecks++;
  res.status(200).json({
    status: 'healthy',
    service: CONFIG.APP_NAME,
    version: CONFIG.APP_VERSION,
    environment: CONFIG.NODE_ENV,
    uptime: Math.floor((Date.now() - METRICS.startTime) / 1000),
    timestamp: new Date().toISOString()
  });
});

// Readiness probe - Is the app ready to serve traffic?
app.get('/ready', async (req, res) => {
  try {
    // Check MongoDB connection
    if (mongoose.connection.readyState !== 1) {
      throw new Error('Database not connected');
    }
    
    // Perform a simple query to verify DB is working
    await Item.findOne().limit(1).lean();
    
    res.status(200).json({
      status: 'ready',
      database: 'connected',
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    res.status(503).json({
      status: 'not ready',
      database: 'disconnected',
      error: error.message
    });
  }
});

// Metrics endpoint for monitoring & auto-scaling decisions
app.get('/metrics', (req, res) => {
  const uptime = Math.floor((Date.now() - METRICS.startTime) / 1000);
  const requestsPerSecond = uptime > 0 ? (METRICS.requestCount / uptime).toFixed(2) : 0;
  const errorRate = METRICS.requestCount > 0 
    ? ((METRICS.errorCount / METRICS.requestCount) * 100).toFixed(2)
    : 0;

  res.status(200).json({
    service: CONFIG.APP_NAME,
    metrics: {
      totalRequests: METRICS.requestCount,
      totalErrors: METRICS.errorCount,
      healthChecks: METRICS.healthChecks,
      apiCalls: METRICS.apiCalls,
      uptimeSeconds: uptime,
      requestsPerSecond: parseFloat(requestsPerSecond),
      errorRate: parseFloat(errorRate),
      memoryUsage: process.memoryUsage(),
      cpuUsage: process.cpuUsage()
    },
    timestamp: new Date().toISOString()
  });
});

// ═══════════════════════════════════════════════════════════════════
// REST API ENDPOINTS
// ═══════════════════════════════════════════════════════════════════

// Get all items with pagination and filtering
app.get('/api/items', async (req, res) => {
  try {
    METRICS.apiCalls++;
    
    const { 
      page = 1, 
      limit = 10, 
      status, 
      sortBy = 'createdAt',
      order = 'desc' 
    } = req.query;
    
    const query = status ? { status } : {};
    const sort = { [sortBy]: order === 'desc' ? -1 : 1 };
    
    const items = await Item.find(query)
      .sort(sort)
      .limit(parseInt(limit))
      .skip((parseInt(page) - 1) * parseInt(limit))
      .lean();
    
    const total = await Item.countDocuments(query);
    
    res.status(200).json({
      success: true,
      data: items,
      pagination: {
        page: parseInt(page),
        limit: parseInt(limit),
        total,
        pages: Math.ceil(total / parseInt(limit))
      }
    });
  } catch (error) {
    METRICS.errorCount++;
    res.status(500).json({ 
      success: false, 
      error: 'Failed to fetch items',
      message: error.message 
    });
  }
});

// Get single item by ID
app.get('/api/items/:id', async (req, res) => {
  try {
    METRICS.apiCalls++;
    
    const item = await Item.findById(req.params.id);
    
    if (!item) {
      return res.status(404).json({ 
        success: false, 
        error: 'Item not found' 
      });
    }
    
    res.status(200).json({ 
      success: true, 
      data: item 
    });
  } catch (error) {
    METRICS.errorCount++;
    res.status(500).json({ 
      success: false, 
      error: 'Failed to fetch item',
      message: error.message 
    });
  }
});

// Create new item
app.post('/api/items', async (req, res) => {
  try {
    METRICS.apiCalls++;
    
    const { name, description, status, priority } = req.body;
    
    // Validation
    if (!name || !description) {
      return res.status(400).json({ 
        success: false, 
        error: 'Name and description are required' 
      });
    }
    
    const item = new Item({ name, description, status, priority });
    await item.save();
    
    res.status(201).json({ 
      success: true, 
      data: item,
      message: 'Item created successfully'
    });
  } catch (error) {
    METRICS.errorCount++;
    res.status(400).json({ 
      success: false, 
      error: 'Failed to create item',
      message: error.message 
    });
  }
});

// Update item
app.put('/api/items/:id', async (req, res) => {
  try {
    METRICS.apiCalls++;
    
    const { name, description, status, priority } = req.body;
    
    const item = await Item.findByIdAndUpdate(
      req.params.id,
      { name, description, status, priority, updatedAt: Date.now() },
      { new: true, runValidators: true }
    );
    
    if (!item) {
      return res.status(404).json({ 
        success: false, 
        error: 'Item not found' 
      });
    }
    
    res.status(200).json({ 
      success: true, 
      data: item,
      message: 'Item updated successfully'
    });
  } catch (error) {
    METRICS.errorCount++;
    res.status(400).json({ 
      success: false, 
      error: 'Failed to update item',
      message: error.message 
    });
  }
});

// Delete item
app.delete('/api/items/:id', async (req, res) => {
  try {
    METRICS.apiCalls++;
    
    const item = await Item.findByIdAndDelete(req.params.id);
    
    if (!item) {
      return res.status(404).json({ 
        success: false, 
        error: 'Item not found' 
      });
    }
    
    res.status(200).json({ 
      success: true, 
      message: 'Item deleted successfully' 
    });
  } catch (error) {
    METRICS.errorCount++;
    res.status(500).json({ 
      success: false, 
      error: 'Failed to delete item',
      message: error.message 
    });
  }
});

// Bulk operations endpoint (for load testing)
app.post('/api/items/bulk', async (req, res) => {
  try {
    METRICS.apiCalls++;
    
    const { items } = req.body;
    
    if (!Array.isArray(items) || items.length === 0) {
      return res.status(400).json({ 
        success: false, 
        error: 'Items array is required' 
      });
    }
    
    const created = await Item.insertMany(items);
    
    res.status(201).json({ 
      success: true, 
      data: created,
      count: created.length,
      message: `${created.length} items created successfully`
    });
  } catch (error) {
    METRICS.errorCount++;
    res.status(400).json({ 
      success: false, 
      error: 'Failed to create items',
      message: error.message 
    });
  }
});

// ═══════════════════════════════════════════════════════════════════
// FRONTEND - SIMPLE REACT-LIKE SPA (SERVED FROM BACKEND)
// ═══════════════════════════════════════════════════════════════════

app.get('/', (req, res) => {
  res.send(`
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>${CONFIG.APP_NAME}</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { 
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Arial, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            padding: 20px;
        }
        .container {
            max-width: 1200px;
            margin: 0 auto;
            background: white;
            border-radius: 15px;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
            padding: 40px;
        }
        h1 { 
            color: #667eea;
            margin-bottom: 10px;
            font-size: 2.5em;
        }
        .badge {
            display: inline-block;
            background: #28a745;
            color: white;
            padding: 5px 15px;
            border-radius: 20px;
            font-size: 0.9em;
            margin-bottom: 30px;
        }
        .stats {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 20px;
            margin: 30px 0;
        }
        .stat-card {
            background: #f8f9fa;
            padding: 20px;
            border-radius: 10px;
            border-left: 4px solid #667eea;
        }
        .stat-card h3 {
            color: #666;
            font-size: 0.9em;
            margin-bottom: 10px;
        }
        .stat-card .value {
            font-size: 2em;
            color: #333;
            font-weight: bold;
        }
        .form-group {
            margin: 20px 0;
        }
        input, textarea {
            width: 100%;
            padding: 12px;
            border: 2px solid #ddd;
            border-radius: 5px;
            font-size: 16px;
            margin: 5px 0;
        }
        button {
            background: #667eea;
            color: white;
            border: none;
            padding: 12px 30px;
            border-radius: 5px;
            cursor: pointer;
            font-size: 16px;
            font-weight: bold;
        }
        button:hover {
            background: #5568d3;
        }
        .items-list {
            margin-top: 30px;
        }
        .item {
            background: #f8f9fa;
            padding: 20px;
            margin: 10px 0;
            border-radius: 10px;
            border-left: 4px solid #28a745;
        }
        .item h3 {
            color: #333;
            margin-bottom: 10px;
        }
        .item p {
            color: #666;
            line-height: 1.6;
        }
        .delete-btn {
            background: #dc3545;
            padding: 8px 16px;
            font-size: 14px;
            margin-top: 10px;
        }
        .footer {
            margin-top: 40px;
            padding-top: 20px;
            border-top: 2px solid #eee;
            text-align: center;
            color: #666;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🚀 ${CONFIG.APP_NAME}</h1>
        <span class="badge">Environment: ${CONFIG.NODE_ENV}</span>
        <span class="badge">Version: ${CONFIG.APP_VERSION}</span>
        
        <div class="stats" id="stats">
            <div class="stat-card">
                <h3>Total Requests</h3>
                <div class="value" id="totalRequests">0</div>
            </div>
            <div class="stat-card">
                <h3>API Calls</h3>
                <div class="value" id="apiCalls">0</div>
            </div>
            <div class="stat-card">
                <h3>Uptime (seconds)</h3>
                <div class="value" id="uptime">0</div>
            </div>
            <div class="stat-card">
                <h3>Requests/Sec</h3>
                <div class="value" id="rps">0</div>
            </div>
        </div>
        
        <div class="form-group">
            <h2>Add New Item</h2>
            <input type="text" id="itemName" placeholder="Item Name" />
            <textarea id="itemDesc" placeholder="Description" rows="3"></textarea>
            <button onclick="createItem()">Add Item</button>
        </div>
        
        <div class="items-list">
            <h2>Items</h2>
            <div id="itemsList"></div>
        </div>
        
        <div class="footer">
            <p>Complete DevOps Pipeline with Auto-Scaling | Powered by Express + MongoDB + Kubernetes</p>
        </div>
    </div>
    
    <script>
        // Fetch and display metrics
        async function updateMetrics() {
            try {
                const res = await fetch('/metrics');
                const data = await res.json();
                document.getElementById('totalRequests').textContent = data.metrics.totalRequests;
                document.getElementById('apiCalls').textContent = data.metrics.apiCalls;
                document.getElementById('uptime').textContent = data.metrics.uptimeSeconds;
                document.getElementById('rps').textContent = data.metrics.requestsPerSecond;
            } catch (error) {
                console.error('Failed to fetch metrics:', error);
            }
        }
        
        // Fetch and display items
        async function loadItems() {
            try {
                const res = await fetch('/api/items');
                const data = await res.json();
                const itemsList = document.getElementById('itemsList');
                
                if (data.success && data.data.length > 0) {
                    itemsList.innerHTML = data.data.map(item => \`
                        <div class="item">
                            <h3>\${item.name}</h3>
                            <p>\${item.description}</p>
                            <p style="color: #999; font-size: 0.9em;">Created: \${new Date(item.createdAt).toLocaleDateString()}</p>
                            <button class="delete-btn" onclick="deleteItem('\${item._id}')">Delete</button>
                        </div>
                    \`).join('');
                } else {
                    itemsList.innerHTML = '<p style="text-align: center; color: #999;">No items yet. Add one above!</p>';
                }
            } catch (error) {
                console.error('Failed to load items:', error);
            }
        }
        
        // Create new item
        async function createItem() {
            const name = document.getElementById('itemName').value;
            const description = document.getElementById('itemDesc').value;
            
            if (!name || !description) {
                alert('Please fill in all fields');
                return;
            }
            
            try {
                const res = await fetch('/api/items', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ name, description })
                });
                
                if (res.ok) {
                    document.getElementById('itemName').value = '';
                    document.getElementById('itemDesc').value = '';
                    loadItems();
                }
            } catch (error) {
                console.error('Failed to create item:', error);
            }
        }
        
        // Delete item
        async function deleteItem(id) {
            if (!confirm('Are you sure?')) return;
            
            try {
                await fetch(\`/api/items/\${id}\`, { method: 'DELETE' });
                loadItems();
            } catch (error) {
                console.error('Failed to delete item:', error);
            }
        }
        
        // Initial load
        updateMetrics();
        loadItems();
        
        // Auto-refresh metrics every 5 seconds
        setInterval(updateMetrics, 5000);
    </script>
</body>
</html>
  `);
});

// ═══════════════════════════════════════════════════════════════════
// ERROR HANDLING
// ═══════════════════════════════════════════════════════════════════

// 404 handler
app.use((req, res) => {
  res.status(404).json({ 
    success: false, 
    error: 'Route not found',
    path: req.path 
  });
});

// Global error handler
app.use((err, req, res, next) => {
  METRICS.errorCount++;
  console.error('Error:', err);
  
  res.status(err.status || 500).json({
    success: false,
    error: err.message || 'Internal server error',
    ...(CONFIG.NODE_ENV === 'development' && { stack: err.stack })
  });
});

// ═══════════════════════════════════════════════════════════════════
// DATABASE CONNECTION & SERVER STARTUP
// ═══════════════════════════════════════════════════════════════════

mongoose.connect(CONFIG.MONGODB_URI, {
  useNewUrlParser: true,
  useUnifiedTopology: true,
})
.then(() => {
  console.log('✅ Connected to MongoDB');
  console.log(`   Database: ${CONFIG.MONGODB_URI}`);
  
  // Start server
  app.listen(CONFIG.PORT, () => {
    console.log('');
    console.log('═══════════════════════════════════════════════════════════');
    console.log(`🚀 ${CONFIG.APP_NAME} is running!`);
    console.log('═══════════════════════════════════════════════════════════');
    console.log(`   Port: ${CONFIG.PORT}`);
    console.log(`   Environment: ${CONFIG.NODE_ENV}`);
    console.log(`   Version: ${CONFIG.APP_VERSION}`);
    console.log(`   Health: http://localhost:${CONFIG.PORT}/health`);
    console.log(`   Metrics: http://localhost:${CONFIG.PORT}/metrics`);
    console.log(`   API: http://localhost:${CONFIG.PORT}/api/items`);
    console.log('═══════════════════════════════════════════════════════════');
  });
})
.catch(err => {
  console.error('❌ MongoDB connection error:', err);
  process.exit(1);
});

// Graceful shutdown
process.on('SIGTERM', () => {
  console.log('SIGTERM received. Closing server gracefully...');
  mongoose.connection.close();
  process.exit(0);
});

module.exports = app;

// ═══════════════════════════════════════════════════════════════════
// END OF COMPLETE APPLICATION
// Features: REST API, Frontend, MongoDB, Health Checks, Metrics
// Ready for: Auto-Scaling, Monitoring, Production Deployment
// ═══════════════════════════════════════════════════════════════════