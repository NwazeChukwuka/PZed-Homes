# P-ZED Homes Database Setup Guide

## 🎯 **Single Database File to Use**

**✅ Use ONLY this file:** `setup_database_complete.sql`

**❌ Do NOT use:** `setup_database.sql` (deleted - was conflicting)

## 🏨 **Your Hotel Departments (Correctly Configured)**

The database now includes your actual hotel departments:

### **Core Departments:**
- **Reception** - Guest services, check-in/out, and front desk operations
- **VIP Bar** - Premium bar service for VIP guests and special events  
- **Outside Bar** - Outdoor bar service and poolside operations
- **Kitchen** - Food preparation, cooking, and culinary services
- **Laundry** - Linen and laundry services for rooms and facilities
- **Mini Mart** - Retail operations and convenience store services

### **Support Departments:**
- **Housekeeping** - Room cleaning, maintenance, and housekeeping services
- **Security** - Hotel security, safety, and surveillance
- **Maintenance** - Facility maintenance and repair services
- **Management** - Administrative and management operations
- **Purchasing** - Procurement and purchasing operations
- **Storekeeping** - Inventory and stock management

## 👥 **Sample Staff (Ready to Use)**

The database includes sample staff profiles for each department:

- **Hotel Owner** (owner@pzed.home) - Full access
- **General Manager** (manager@pzed.home) - Management access
- **Reception Manager** (reception@pzed.home) - Reception + Management
- **VIP Bar Manager** (vipbar@pzed.home) - VIP Bar + Management
- **Outside Bar Staff** (outsidebar@pzed.home) - Outside Bar operations
- **Head Chef** (chef@pzed.home) - Kitchen + Management
- **Laundry Supervisor** (laundry@pzed.home) - Laundry + Management
- **Mini Mart Manager** (minimart@pzed.home) - Mini Mart + Management
- **Housekeeping Supervisor** (housekeeping@pzed.home) - Housekeeping + Management
- **Security Manager** (security@pzed.home) - Security + Management
- **Purchasing Manager** (purchasing@pzed.home) - Purchasing + Management
- **Storekeeper** (storekeeper@pzed.home) - Storekeeping operations
- **Accountant** (accountant@pzed.home) - Financial management
- **HR Manager** (hr@pzed.home) - Human resources + Management

## 🍽️ **Menu Items by Department**

### **Kitchen Items:**
- Jollof Rice, Fried Rice, Chicken Curry, Beef Steak, Club Sandwich, Caesar Salad

### **VIP Bar Items:**
- Premium Whiskey, Champagne, Craft Cocktails

### **Outside Bar Items:**
- Heineken Beer, Red Wine, Coca Cola, Sprite

### **Mini Mart Items:**
- Bottled Water, Snacks Pack, Toiletries

## 🚀 **How to Set Up**

1. **Open Supabase Dashboard**
2. **Go to SQL Editor**
3. **Copy and paste the entire content of `setup_database_complete.sql`**
4. **Run the script**
5. **Verify all tables are created**
6. **Test with sample login: `owner@pzed.home`**

## ✅ **What's Included**

- ✅ **All Tables** - Complete database schema
- ✅ **Your Departments** - Reception, VIP Bar, Outside Bar, Kitchen, Laundry, Mini Mart, etc.
- ✅ **Sample Staff** - Ready-to-use user accounts
- ✅ **Menu Items** - Department-specific items
- ✅ **Security Policies** - Row Level Security (RLS)
- ✅ **Sample Data** - Rooms, bookings, stock items
- ✅ **Helper Functions** - Database functions for common operations

## 🔧 **System Integration**

This database works perfectly with:
- ✅ **Role-Based Access Control** - Each staff member has appropriate permissions
- ✅ **Department Workflows** - Kitchen → Bar → Reception flow
- ✅ **Mini Mart Operations** - Separate from room service
- ✅ **Purchasing System** - Purchaser and Storekeeper workflows
- ✅ **Inventory Management** - Stock tracking by department
- ✅ **Financial Reporting** - Department-wise revenue tracking

## 📱 **Testing the System**

1. **Login as Owner:** `owner@pzed.home` (Full access)
2. **Login as Reception:** `reception@pzed.home` (Reception + Mini Mart)
3. **Login as Kitchen:** `chef@pzed.home` (Kitchen operations)
4. **Login as VIP Bar:** `vipbar@pzed.home` (VIP Bar management)
5. **Login as Mini Mart:** `minimart@pzed.home` (Mini Mart operations)

## 🎉 **Ready for Production**

Your P-ZED Homes system is now configured with:
- ✅ **Correct Hotel Departments**
- ✅ **Proper Staff Roles**
- ✅ **Department-Specific Menu Items**
- ✅ **Complete Database Schema**
- ✅ **Security and Permissions**
- ✅ **Sample Data for Testing**

**Use only `setup_database_complete.sql` - this is your single source of truth!** 🎯
