# Odoo 19.0 API Documentation

**Complete Reference for Integrating with Odoo**

---

## Table of Contents

1. [Overview](#overview)
2. [Authentication](#authentication)
3. [XML-RPC API](#xml-rpc-api)
4. [JSON-RPC API](#json-rpc-api)
5. [RESTful HTTP API](#restful-http-api)
6. [Web Controllers](#web-controllers)
7. [ORM Methods Reference](#orm-methods-reference)
8. [Common Patterns](#common-patterns)
9. [Error Handling](#error-handling)
10. [Security & Best Practices](#security--best-practices)

---

## Overview

Odoo provides multiple API interfaces for external integrations:

| API Type | Protocol | Use Case | Authentication |
|----------|----------|----------|----------------|
| **XML-RPC** | HTTP/XML | Legacy integrations, simple CRUD | Username/Password or API Key |
| **JSON-RPC** | HTTP/JSON | Modern integrations, web clients | Session-based or API Key |
| **HTTP Controllers** | REST-like | Custom endpoints, webhooks | Configurable per route |
| **ORM API** | Python (internal) | Module development | Internal (env context) |

**Base URL Structure:**
```
http://localhost:8069        # Development
https://yourdomain.com       # Production
```

---

## Authentication

### 1. Password Authentication

**Standard Login (creates session):**
```python
# Python example
import xmlrpc.client

url = 'http://localhost:8069'
db = 'odoo_dev'
username = 'admin'
password = 'admin'

common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
uid = common.authenticate(db, username, password, {})
```

**Response:**
- Success: Returns user ID (integer)
- Failure: Returns `False`

### 2. API Keys (Recommended for Integrations)

When **MFA/TOTP is enabled**, passwords cannot be used for RPC — use API keys instead.

**Generate API Key:**
1. Go to **Settings → Users → (user) → Account Security tab**
2. Click **New API Key**
3. Set description and scope
4. Copy the key (shown only once)

**Usage:**
```python
# Replace password with API key
uid = common.authenticate(db, username, api_key, {})
```

### 3. Session-Based (Web/JSON-RPC)

```javascript
// JavaScript example (JSON-RPC)
fetch('/web/session/authenticate', {
    method: 'POST',
    headers: {'Content-Type': 'application/json'},
    body: JSON.stringify({
        jsonrpc: "2.0",
        method: "call",
        params: {
            db: "odoo_dev",
            login: "admin",
            password: "admin"
        },
        id: 1
    })
})
```

**Session Cookie:** Server returns `session_id` cookie — include in subsequent requests.

---

## XML-RPC API

### Endpoints

| Endpoint | Purpose |
|----------|---------|
| `/xmlrpc/2/common` | Version info, authentication |
| `/xmlrpc/2/object` | Model operations (CRUD) |
| `/xmlrpc/2/db` | Database management (create/drop/list) |

### Common Service

**Get Server Version:**
```python
common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
version_info = common.version()
```

**Response:**
```python
{
    'server_version': '19.0',
    'server_version_info': [19, 0, 0, 'final', 0],
    'server_serie': '19.0',
    'protocol_version': 1
}
```

### Object Service

**Execute Methods:**
```python
models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')

# Method signature:
# execute_kw(db, uid, password, model, method, [args], {kwargs})

# Search
ids = models.execute_kw(
    db, uid, password,
    'res.partner', 'search',
    [[['is_company', '=', True]]],
    {'limit': 5}
)

# Read
records = models.execute_kw(
    db, uid, password,
    'res.partner', 'read',
    [ids],
    {'fields': ['name', 'email', 'phone']}
)

# Search and Read (combined)
partners = models.execute_kw(
    db, uid, password,
    'res.partner', 'search_read',
    [[['customer_rank', '>', 0]]],
    {'fields': ['name', 'email'], 'limit': 10, 'offset': 0}
)

# Create
partner_id = models.execute_kw(
    db, uid, password,
    'res.partner', 'create',
    [{
        'name': 'New Company',
        'email': 'info@company.com',
        'is_company': True,
        'phone': '+32 2 123 4567'
    }]
)

# Write (update)
models.execute_kw(
    db, uid, password,
    'res.partner', 'write',
    [[partner_id], {'phone': '+32 2 999 8888'}]
)

# Unlink (delete)
models.execute_kw(
    db, uid, password,
    'res.partner', 'unlink',
    [[partner_id]]
)
```

### Database Service

```python
db_service = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/db')

# List databases
databases = db_service.list()

# Create database
db_service.create_database(
    master_password,  # from odoo.conf [options] admin_passwd
    'new_db_name',
    True,             # demo data
    'en_US',          # language
    'admin_password', # admin user password
    'admin',          # admin login
    'US',             # country code
    '+1234567890'     # phone
)

# Drop database
db_service.drop(master_password, 'db_to_delete')

# Duplicate database
db_service.duplicate_database(
    master_password,
    'source_db',
    'target_db'
)

# Backup database (returns base64-encoded zip)
backup_data = db_service.dump(master_password, 'db_name', 'zip')

# Restore database
db_service.restore(
    master_password,
    'new_db_name',
    backup_data  # base64-encoded zip from dump
)
```

---

## JSON-RPC API

**Base Endpoint:** `/web/dataset/call_kw` or `/web/dataset/call_button`

**Request Format:**
```json
{
    "jsonrpc": "2.0",
    "method": "call",
    "params": {
        "model": "res.partner",
        "method": "search_read",
        "args": [
            [["is_company", "=", true]]
        ],
        "kwargs": {
            "fields": ["name", "email", "phone"],
            "limit": 10,
            "context": {}
        }
    },
    "id": 1
}
```

**Response Format:**
```json
{
    "jsonrpc": "2.0",
    "result": [
        {
            "id": 14,
            "name": "Azure Interior",
            "email": "azure.Interior24@example.com",
            "phone": "+1 555-555-5555"
        }
    ],
    "id": 1
}
```

### JavaScript Client Example

```javascript
class OdooClient {
    constructor(baseUrl, db) {
        this.baseUrl = baseUrl;
        this.db = db;
        this.sessionId = null;
    }

    async authenticate(login, password) {
        const response = await fetch(`${this.baseUrl}/web/session/authenticate`, {
            method: 'POST',
            headers: {'Content-Type': 'application/json'},
            body: JSON.stringify({
                jsonrpc: "2.0",
                method: "call",
                params: {db: this.db, login, password},
                id: 1
            })
        });
        const data = await response.json();
        if (data.result && data.result.uid) {
            this.sessionId = response.headers.get('set-cookie');
            return data.result.uid;
        }
        throw new Error('Authentication failed');
    }

    async call(model, method, args = [], kwargs = {}) {
        const response = await fetch(`${this.baseUrl}/web/dataset/call_kw`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'Cookie': this.sessionId
            },
            body: JSON.stringify({
                jsonrpc: "2.0",
                method: "call",
                params: {model, method, args, kwargs},
                id: Math.floor(Math.random() * 1000000)
            })
        });
        const data = await response.json();
        if (data.error) {
            throw new Error(data.error.data.message);
        }
        return data.result;
    }

    async searchRead(model, domain, fields, limit = 80, offset = 0) {
        return this.call(model, 'search_read', [domain], {
            fields, limit, offset, context: {}
        });
    }

    async create(model, values) {
        return this.call(model, 'create', [values]);
    }

    async write(model, ids, values) {
        return this.call(model, 'write', [ids, values]);
    }

    async unlink(model, ids) {
        return this.call(model, 'unlink', [ids]);
    }
}

// Usage
const client = new OdooClient('http://localhost:8069', 'odoo_dev');
await client.authenticate('admin', 'admin');

const partners = await client.searchRead(
    'res.partner',
    [['customer_rank', '>', 0]],
    ['name', 'email', 'phone'],
    10
);
console.log(partners);
```

---

## RESTful HTTP API

Odoo doesn't have a pure REST API out of the box, but you can create custom controllers.

### Creating a Custom Controller

**File:** `addons/my_module/controllers/api.py`

```python
from odoo import http
from odoo.http import request, Response
import json

class MyAPI(http.Controller):

    @http.route('/api/partners', type='http', auth='user', methods=['GET'], csrf=False)
    def get_partners(self, **kwargs):
        """GET /api/partners?limit=10&offset=0"""
        limit = int(kwargs.get('limit', 80))
        offset = int(kwargs.get('offset', 0))
        
        partners = request.env['res.partner'].search_read(
            [['customer_rank', '>', 0]],
            ['name', 'email', 'phone'],
            limit=limit,
            offset=offset
        )
        
        return Response(
            json.dumps({'data': partners, 'count': len(partners)}),
            content_type='application/json',
            status=200
        )

    @http.route('/api/partners', type='json', auth='user', methods=['POST'], csrf=False)
    def create_partner(self, **kwargs):
        """POST /api/partners with JSON body"""
        data = request.jsonrequest
        partner = request.env['res.partner'].create({
            'name': data.get('name'),
            'email': data.get('email'),
            'phone': data.get('phone'),
            'is_company': data.get('is_company', False)
        })
        return {'id': partner.id, 'name': partner.name}

    @http.route('/api/partners/<int:partner_id>', type='http', auth='user', methods=['PUT'], csrf=False)
    def update_partner(self, partner_id, **kwargs):
        """PUT /api/partners/123 with form data"""
        partner = request.env['res.partner'].browse(partner_id)
        if not partner.exists():
            return Response(
                json.dumps({'error': 'Partner not found'}),
                content_type='application/json',
                status=404
            )
        
        partner.write({
            'name': kwargs.get('name', partner.name),
            'email': kwargs.get('email', partner.email),
            'phone': kwargs.get('phone', partner.phone)
        })
        
        return Response(
            json.dumps({'id': partner.id, 'name': partner.name}),
            content_type='application/json',
            status=200
        )

    @http.route('/api/partners/<int:partner_id>', type='http', auth='user', methods=['DELETE'], csrf=False)
    def delete_partner(self, partner_id, **kwargs):
        """DELETE /api/partners/123"""
        partner = request.env['res.partner'].browse(partner_id)
        if not partner.exists():
            return Response(
                json.dumps({'error': 'Partner not found'}),
                content_type='application/json',
                status=404
            )
        
        partner.unlink()
        return Response(
            json.dumps({'message': 'Partner deleted'}),
            content_type='application/json',
            status=200
        )
```

**Register Controller:**

**File:** `addons/my_module/controllers/__init__.py`
```python
from . import api
```

**File:** `addons/my_module/__init__.py`
```python
from . import controllers
```

### Authentication Options for Routes

```python
@http.route('/my/endpoint', auth='public')   # No auth required
@http.route('/my/endpoint', auth='none')     # No DB connection, no session
@http.route('/my/endpoint', auth='user')     # Requires logged-in user
@http.route('/my/endpoint', auth='api_key')  # Requires valid API key (header: api-key: KEY)
```

---

## Web Controllers

### Standard Web Endpoints

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/web/session/authenticate` | POST | Login (creates session) |
| `/web/session/destroy` | POST | Logout |
| `/web/session/get_session_info` | POST | Get current user info |
| `/web/dataset/call_kw` | POST | Call any model method |
| `/web/dataset/search_read` | POST | Search and read records |
| `/web/dataset/call_button` | POST | Execute button action |
| `/web/database/list` | POST | List databases |
| `/web/database/create` | POST | Create database |
| `/web/database/manager` | GET | Database manager UI |
| `/web/binary/upload_attachment` | POST | Upload file |
| `/web/content/<int:id>` | GET | Download attachment by ID |
| `/web/image/<model>/<field>/<id>` | GET | Fetch image field |

### Session Management

```python
# Get session info
POST /web/session/get_session_info
{
    "jsonrpc": "2.0",
    "method": "call",
    "params": {},
    "id": 1
}

# Response
{
    "result": {
        "uid": 2,
        "username": "admin",
        "name": "Mitchell Admin",
        "partner_id": 3,
        "company_id": 1,
        "db": "odoo_dev",
        "currencies": {...},
        "user_companies": {...},
        "is_admin": true,
        "is_system": true,
        ...
    }
}
```

---

## ORM Methods Reference

### Search Methods

#### `search(domain, offset=0, limit=None, order=None, count=False)`

```python
# Find all companies
ids = env['res.partner'].search([('is_company', '=', True)])

# Find first 10 customers, ordered by name
ids = env['res.partner'].search(
    [('customer_rank', '>', 0)],
    limit=10,
    order='name asc'
)

# Count records
count = env['res.partner'].search_count([('is_company', '=', True)])
```

**Domain Operators:**
```python
[('field', '=', value)]       # Equals
[('field', '!=', value)]      # Not equals
[('field', '>', value)]       # Greater than
[('field', '>=', value)]      # Greater or equal
[('field', '<', value)]       # Less than
[('field', '<=', value)]      # Less or equal
[('field', 'like', value)]    # SQL LIKE (case-sensitive)
[('field', 'ilike', value)]   # SQL ILIKE (case-insensitive)
[('field', 'in', [v1, v2])]   # In list
[('field', 'not in', [v])]    # Not in list
[('field', '=?', value)]      # Equals if value is not None/False
[('field', '=like', 'val%')]  # LIKE with pattern
[('field', '=ilike', 'val%')] # ILIKE with pattern

# Boolean combinations
['|', ('field1', '=', val1), ('field2', '=', val2)]  # OR
['&', ('field1', '=', val1), ('field2', '=', val2)]  # AND (default)
['!', ('field', '=', value)]                         # NOT
```

#### `search_read(domain, fields=None, offset=0, limit=None, order=None)`

```python
# Combined search + read (more efficient)
partners = env['res.partner'].search_read(
    [('is_company', '=', True)],
    fields=['name', 'email', 'phone', 'country_id'],
    limit=20,
    order='name'
)
# Returns: [{'id': 1, 'name': '...', 'email': '...', ...}, ...]
```

### Read Methods

#### `read(fields=None, load='_classic_read')`

```python
# Read specific fields
partners = env['res.partner'].browse([1, 2, 3])
data = partners.read(['name', 'email', 'phone'])
# Returns: [{'id': 1, 'name': '...', ...}, ...]
```

#### `browse(ids)`

```python
# Get recordset from IDs
partner = env['res.partner'].browse(14)
print(partner.name)  # Direct field access

# Multiple records
partners = env['res.partner'].browse([1, 2, 3])
for p in partners:
    print(p.name)
```

### Write Methods

#### `create(vals_list)`

```python
# Create single record
partner = env['res.partner'].create({
    'name': 'John Doe',
    'email': 'john@example.com',
    'phone': '+32 2 123 4567',
    'is_company': False
})
# Returns: recordset with new ID

# Create multiple records
partners = env['res.partner'].create([
    {'name': 'Company A', 'is_company': True},
    {'name': 'Company B', 'is_company': True}
])
# Returns: recordset with all new IDs
```

#### `write(vals)`

```python
# Update records
partner = env['res.partner'].browse(14)
partner.write({'phone': '+32 2 999 8888'})

# Update multiple
partners = env['res.partner'].search([('city', '=', 'Brussels')])
partners.write({'country_id': env.ref('base.be').id})
```

#### `unlink()`

```python
# Delete records
partner = env['res.partner'].browse(14)
partner.unlink()

# Delete multiple
old_partners = env['res.partner'].search([
    ('create_date', '<', '2020-01-01')
])
old_partners.unlink()
```

### Relation Fields

#### Many2one

```python
# Read
partner = env['res.partner'].browse(14)
country_name = partner.country_id.name  # Access related record

# Write
partner.write({'country_id': env.ref('base.us').id})

# Search
partners_in_us = env['res.partner'].search([
    ('country_id', '=', env.ref('base.us').id)
])

# Search by related field
partners = env['res.partner'].search([
    ('country_id.code', '=', 'US')
])
```

#### One2many / Many2many

```python
# Read
user = env['res.users'].browse(2)
group_names = user.groups_id.mapped('name')  # List of group names

# Write - Replace all
user.write({'groups_id': [(6, 0, [1, 2, 3])]})

# Write - Add records
user.write({'groups_id': [(4, group_id)]})

# Write - Remove records
user.write({'groups_id': [(3, group_id)]})

# Write - Create related record
partner.write({
    'child_ids': [(0, 0, {
        'name': 'Contact Name',
        'email': 'contact@example.com'
    })]
})

# Write commands reference:
# (0, 0, values)      - Create new record and link
# (1, id, values)     - Update linked record
# (2, id)             - Delete linked record (unlink + delete)
# (3, id)             - Unlink record (delete relationship, not record)
# (4, id)             - Link existing record
# (5,)                - Unlink all
# (6, 0, [ids])       - Replace all with ids list
```

### Advanced Methods

#### `filtered(func)` / `filtered_domain(domain)`

```python
# Filter recordset with function
active_partners = partners.filtered(lambda p: p.active)

# Filter with domain
company_partners = partners.filtered_domain([('is_company', '=', True)])
```

#### `mapped(field_or_func)`

```python
# Extract field values
emails = partners.mapped('email')  # ['email1@...', 'email2@...', ...]

# Map related field
country_names = partners.mapped('country_id.name')

# Map with function
upper_names = partners.mapped(lambda p: p.name.upper())
```

#### `sorted(key=None, reverse=False)`

```python
# Sort by field
sorted_partners = partners.sorted('name')

# Sort with custom key
sorted_partners = partners.sorted(lambda p: p.credit_limit, reverse=True)
```

#### `exists()`

```python
# Check if records still exist in DB
partner = env['res.partner'].browse(99999)
if partner.exists():
    print(partner.name)
else:
    print("Partner does not exist")
```

#### `ensure_one()`

```python
# Ensure recordset has exactly one record (raises ValueError otherwise)
def get_partner_email(self):
    self.ensure_one()
    return self.email
```

---

## Common Patterns

### 1. Context Management

```python
# Set context for this recordset only
partners_fr = env['res.partner'].with_context(lang='fr_FR').browse([1, 2, 3])
print(partners_fr[0].country_id.name)  # Returns French translation

# Common context keys:
env['model'].with_context(
    lang='en_US',              # Language for translations
    tz='Europe/Brussels',      # Timezone
    active_test=False,         # Include archived records
    force_company=1,           # Force specific company
    tracking_disable=True,     # Disable mail tracking
    mail_create_nosubscribe=True,  # Don't auto-subscribe creator
)
```

### 2. Environment Switching

```python
# Switch user (sudo)
partner = env['res.partner'].sudo().browse(14)  # Execute as SUPERUSER

# Switch to specific user
partner = env['res.partner'].with_user(user_id).browse(14)

# Switch company
partner = env['res.partner'].with_company(company_id).browse(14)
```

### 3. Transactions & Commits

```python
# Manual commit (use sparingly)
env.cr.commit()

# Rollback on error
try:
    partner.write({'invalid_field': 'value'})
except Exception:
    env.cr.rollback()
    raise

# Savepoint
with env.cr.savepoint():
    # Changes here are rolled back if exception occurs
    partner.write({'name': 'New Name'})
```

### 4. Batch Operations

```python
# Create many records efficiently
partners = env['res.partner'].create([
    {'name': f'Partner {i}'} for i in range(1000)
])

# Update in batches
BATCH_SIZE = 100
partner_ids = env['res.partner'].search([('active', '=', False)])
for batch_start in range(0, len(partner_ids), BATCH_SIZE):
    batch = partner_ids[batch_start:batch_start + BATCH_SIZE]
    batch.write({'active': True})
    env.cr.commit()  # Commit each batch
```

### 5. SQL Queries (Use with Caution)

```python
# Raw SQL - bypasses ORM (no access rights, no computed fields)
env.cr.execute("""
    SELECT id, name, email
    FROM res_partner
    WHERE is_company = true
    LIMIT 10
""")
results = env.cr.dictfetchall()  # [{'id': 1, 'name': '...', ...}, ...]

# Always use parameterized queries to prevent SQL injection
env.cr.execute("""
    SELECT id, name
    FROM res_partner
    WHERE country_id = %s
""", (country_id,))
```

---

## Error Handling

### Common Exceptions

```python
from odoo.exceptions import (
    AccessDenied,      # Authentication failed
    AccessError,       # Permission denied
    UserError,         # Validation error (shown to user)
    ValidationError,   # Field validation failed
    MissingError,      # Record doesn't exist
    RedirectWarning,   # Show warning with action link
    ConcurrencyError,  # Record was modified by another transaction
)

# Example usage
from odoo import models, fields, api
from odoo.exceptions import UserError

class MyModel(models.Model):
    _name = 'my.model'
    
    amount = fields.Float()
    
    @api.constrains('amount')
    def _check_amount(self):
        for record in self:
            if record.amount < 0:
                raise ValidationError("Amount cannot be negative")
    
    def process_payment(self):
        self.ensure_one()
        if self.amount <= 0:
            raise UserError("Cannot process payment with zero or negative amount")
```

### XML-RPC Error Handling

```python
import xmlrpc.client
from xmlrpc.client import Fault

try:
    models.execute_kw(db, uid, password, 'res.partner', 'read', [[999999]])
except Fault as e:
    print(f"Error: {e.faultCode} - {e.faultString}")
```

### JSON-RPC Error Handling

```javascript
const response = await fetch('/web/dataset/call_kw', {
    method: 'POST',
    headers: {'Content-Type': 'application/json'},
    body: JSON.stringify({...})
});

const data = await response.json();

if (data.error) {
    console.error('Error:', data.error.data.message);
    console.error('Type:', data.error.data.name);  // e.g., "odoo.exceptions.UserError"
    console.error('Debug:', data.error.data.debug);
}
```

---

## Security & Best Practices

### 1. Access Rights

```xml
<!-- security/ir.model.access.csv -->
id,name,model_id:id,group_id:id,perm_read,perm_write,perm_create,perm_unlink
access_my_model_user,my.model.user,model_my_model,base.group_user,1,1,1,0
access_my_model_manager,my.model.manager,model_my_model,base.group_system,1,1,1,1
```

### 2. Record Rules (Row-Level Security)

```python
# Only see own records
<record id="my_model_personal_rule" model="ir.rule">
    <field name="name">Personal Records</field>
    <field name="model_id" ref="model_my_model"/>
    <field name="domain_force">[('user_id', '=', user.id)]</field>
    <field name="groups" eval="[(4, ref('base.group_user'))]"/>
</record>

# See all company records
<record id="my_model_company_rule" model="ir.rule">
    <field name="name">Company Records</field>
    <field name="model_id" ref="model_my_model"/>
    <field name="domain_force">[('company_id', 'in', company_ids)]</field>
    <field name="groups" eval="[(4, ref('base.group_user'))]"/>
</record>
```

### 3. API Rate Limiting

```python
from odoo.addons.web.controllers.utils import ensure_db
from werkzeug.exceptions import TooManyRequests
import time

class RateLimitedAPI(http.Controller):
    _rate_limit = {}  # Store: {ip: [(timestamp1, timestamp2, ...)]}
    
    def _check_rate_limit(self, ip, max_requests=100, window=60):
        """Allow max_requests per window (seconds)"""
        now = time.time()
        
        # Clean old entries
        if ip in self._rate_limit:
            self._rate_limit[ip] = [
                ts for ts in self._rate_limit[ip]
                if now - ts < window
            ]
        else:
            self._rate_limit[ip] = []
        
        if len(self._rate_limit[ip]) >= max_requests:
            raise TooManyRequests("Rate limit exceeded")
        
        self._rate_limit[ip].append(now)
    
    @http.route('/api/limited', auth='public')
    def limited_endpoint(self, **kwargs):
        self._check_rate_limit(request.httprequest.remote_addr)
        return {'message': 'OK'}
```

### 4. Input Validation

```python
import re
from odoo.exceptions import UserError

class MyAPI(http.Controller):
    
    @http.route('/api/create_partner', type='json', auth='user')
    def create_partner(self, name, email, **kwargs):
        # Validate email
        if not re.match(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$', email):
            raise UserError("Invalid email format")
        
        # Validate name
        if len(name) < 2 or len(name) > 100:
            raise UserError("Name must be between 2 and 100 characters")
        
        # Sanitize input
        name = name.strip()
        email = email.lower().strip()
        
        partner = request.env['res.partner'].create({
            'name': name,
            'email': email
        })
        
        return {'id': partner.id}
```

### 5. API Key Authentication

```python
class SecureAPI(http.Controller):
    
    def _authenticate_api_key(self):
        """Verify API key from request header"""
        api_key = request.httprequest.headers.get('X-API-Key')
        if not api_key:
            raise AccessDenied("API key required")
        
        # Verify key exists and is valid
        key_record = request.env['res.users.apikeys'].sudo().search([
            ('key', '=', api_key),
            ('user_id.active', '=', True)
        ], limit=1)
        
        if not key_record:
            raise AccessDenied("Invalid API key")
        
        # Update environment with the key's user
        request.update_env(user=key_record.user_id.id)
        return key_record.user_id
    
    @http.route('/api/secure/partners', type='json', auth='none')
    def get_partners_secure(self, **kwargs):
        user = self._authenticate_api_key()
        
        partners = request.env['res.partner'].search_read(
            [('user_id', '=', user.id)],
            ['name', 'email']
        )
        
        return {'data': partners}
```

### 6. CORS Configuration

```python
# In controller
from odoo.http import Response

class CorsAPI(http.Controller):
    
    @http.route('/api/public', type='http', auth='none', cors='*', csrf=False)
    def public_endpoint(self, **kwargs):
        return Response(
            json.dumps({'message': 'Hello'}),
            content_type='application/json',
            headers={
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
                'Access-Control-Allow-Headers': 'Content-Type, Authorization'
            }
        )
```

---

## Example: Complete Integration

### Python Client (XML-RPC)

```python
#!/usr/bin/env python3
"""Complete Odoo XML-RPC client example"""

import xmlrpc.client
from datetime import datetime


class OdooClient:
    def __init__(self, url, db, username, password):
        self.url = url
        self.db = db
        self.username = username
        self.password = password
        
        self.common = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/common')
        self.models = xmlrpc.client.ServerProxy(f'{url}/xmlrpc/2/object')
        
        # Authenticate
        self.uid = self.common.authenticate(db, username, password, {})
        if not self.uid:
            raise Exception("Authentication failed")
    
    def execute(self, model, method, *args, **kwargs):
        """Execute any model method"""
        return self.models.execute_kw(
            self.db, self.uid, self.password,
            model, method, args, kwargs
        )
    
    def search(self, model, domain, **kwargs):
        """Search records"""
        return self.execute(model, 'search', domain, kwargs)
    
    def read(self, model, ids, fields):
        """Read records"""
        return self.execute(model, 'read', ids, {'fields': fields})
    
    def search_read(self, model, domain, fields, **kwargs):
        """Search and read in one call"""
        return self.execute(model, 'search_read', domain, {
            'fields': fields,
            **kwargs
        })
    
    def create(self, model, values):
        """Create record"""
        return self.execute(model, 'create', values)
    
    def write(self, model, ids, values):
        """Update records"""
        return self.execute(model, 'write', ids, values)
    
    def unlink(self, model, ids):
        """Delete records"""
        return self.execute(model, 'unlink', ids)


# Usage example
if __name__ == '__main__':
    client = OdooClient(
        url='http://localhost:8069',
        db='odoo_dev',
        username='admin',
        password='admin'
    )
    
    # Create a partner
    partner_id = client.create('res.partner', {
        'name': 'API Test Company',
        'email': 'api@test.com',
        'phone': '+32 2 123 4567',
        'is_company': True
    })
    print(f"Created partner ID: {partner_id}")
    
    # Search and read
    partners = client.search_read(
        'res.partner',
        [['customer_rank', '>', 0]],
        ['name', 'email', 'phone'],
        limit=5
    )
    
    for partner in partners:
        print(f"{partner['name']}: {partner['email']}")
    
    # Update
    client.write('res.partner', [partner_id], {
        'phone': '+32 2 999 8888'
    })
    print("Partner updated")
    
    # Delete
    client.unlink('res.partner', [partner_id])
    print("Partner deleted")
```

---

## Additional Resources

### Official Documentation
- **Developer Documentation:** https://www.odoo.com/documentation/19.0/developer.html
- **API Reference:** https://www.odoo.com/documentation/19.0/developer/reference.html
- **ORM API:** https://www.odoo.com/documentation/19.0/developer/reference/backend/orm.html

### Community Resources
- **Odoo Experience Presentations:** https://www.odoo.com/slides/all/tag/odoo-experience
- **GitHub Repository:** https://github.com/odoo/odoo
- **Community Forum:** https://www.odoo.com/forum

### Tools & Libraries
- **OdooRPC (Python):** https://github.com/OCA/odoorpc
- **Odoo External API (Python):** https://github.com/OCA/odoo-external-api
- **Odoo TypeScript SDK:** https://github.com/odoo/odoo-ts-sdk

---

**Document Version:** 1.0  
**Odoo Version:** 19.0  
**Last Updated:** March 2026

For questions or contributions, please open an issue in the repository.
