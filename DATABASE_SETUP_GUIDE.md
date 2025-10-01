# P-ZED Homes Database Setup Guide

## Overview
This guide will help you set up the complete database schema for the P-ZED Homes Hotel Management System on Supabase.

## Prerequisites
- Supabase account and project
- Database access permissions
- Basic SQL knowledge

## Step 1: Create Supabase Project
1. Go to [supabase.com](https://supabase.com)
2. Create a new project
3. Note down your project URL and anon key

## Step 2: Run Database Schema
1. Open your Supabase project dashboard
2. Go to SQL Editor
3. Copy and paste the contents of `setup_database_complete.sql`
4. Execute the script

## Step 3: Configure Authentication
1. Go to Authentication > Settings
2. Enable email authentication
3. Configure email templates if needed
4. Set up any additional auth providers (optional)

## Step 4: Configure Row Level Security (RLS)
The database schema includes comprehensive RLS policies that are automatically created. These policies ensure:
- Users can only access data they're authorized to see
- Role-based access control is enforced
- Data security is maintained

## Step 5: Test the Setup
1. Create a test user account
2. Assign appropriate roles
3. Test different user permissions
4. Verify data access controls

## Database Schema Overview

### Core Tables
- **profiles**: User accounts and roles
- **room_types**: Room categories and pricing
- **rooms**: Individual room records
- **bookings**: Guest reservations
- **booking_charges**: Additional charges for bookings

### Inventory Management
- **stock_items**: Inventory items
- **stock_transactions**: Stock movement records
- **inventory_items**: Alternative inventory system
- **inventory_transactions**: Inventory movement records
- **locations**: Storage locations
- **department_transfers**: Inter-department transfers

### Operations
- **menu_items**: Food and beverage items
- **categories**: Item categories
- **departments**: Hotel departments
- **work_orders**: Maintenance requests
- **maintenance_work_orders**: Room maintenance
- **attendance_records**: Staff attendance

### Financial
- **expenses**: Hotel expenses
- **expense_categories**: Expense types
- **assets**: Hotel assets

### Communication
- **posts**: Internal communications
- **notifications**: User notifications

## Key Features

### Role-Based Access Control
The system supports multiple user roles:
- **Owner**: Full system access
- **Manager**: Management-level access
- **Receptionist**: Front desk operations
- **Housekeeper**: Room management
- **Kitchen Staff**: Food service
- **Bartender**: Beverage service
- **Security**: Security operations
- **Purchaser**: Procurement
- **Storekeeper**: Inventory management
- **HR**: Human resources
- **Accountant**: Financial operations

### Real-time Features
- Live notifications
- Real-time stock updates
- Attendance tracking
- Booking status updates

### Data Integrity
- Foreign key constraints
- Check constraints for data validation
- Automatic timestamp updates
- Comprehensive indexing

## Sample Data
The schema includes sample data for:
- Room types and rooms
- Menu items and categories
- Stock items and transactions
- Sample bookings
- Department structure
- User roles and permissions

## Performance Optimization
- Strategic indexing for common queries
- Optimized views for reporting
- Efficient RLS policies
- Connection pooling support

## Security Features
- Row Level Security (RLS) enabled on all tables
- Role-based access policies
- Data encryption at rest
- Secure authentication

## Backup and Recovery
- Regular automated backups
- Point-in-time recovery
- Data export capabilities
- Schema versioning

## Monitoring and Analytics
- Built-in performance monitoring
- Query optimization insights
- Usage analytics
- Error tracking

## Troubleshooting

### Common Issues
1. **Permission Errors**: Ensure RLS policies are correctly configured
2. **Connection Issues**: Verify Supabase credentials
3. **Data Not Loading**: Check user roles and permissions
4. **Performance Issues**: Review indexing strategy

### Support
- Check Supabase documentation
- Review error logs in dashboard
- Test with sample data
- Verify user permissions

## Next Steps
1. Configure your Flutter app with Supabase credentials
2. Test all user roles and permissions
3. Customize the schema for your specific needs
4. Set up monitoring and alerts
5. Train staff on the new system

## Maintenance
- Regular database maintenance
- Performance monitoring
- Security updates
- Backup verification
- User access reviews

This database setup provides a solid foundation for the P-ZED Homes Hotel Management System with comprehensive features for hotel operations, inventory management, staff coordination, and guest services.
