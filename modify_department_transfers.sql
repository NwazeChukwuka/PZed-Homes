-- Migration: Modify department_transfers for inter-department transfers
-- This script modifies the department_transfers table to support transfers between any departments

-- Add new columns for source and destination departments
ALTER TABLE public.department_transfers 
ADD COLUMN IF NOT EXISTS source_department_id UUID REFERENCES public.locations(id) ON DELETE CASCADE,
ADD COLUMN IF NOT EXISTS destination_department_id UUID REFERENCES public.locations(id) ON DELETE CASCADE;

-- Create index for performance
CREATE INDEX IF NOT EXISTS idx_department_transfers_source ON public.department_transfers(source_department_id);
CREATE INDEX IF NOT EXISTS idx_department_transfers_destination ON public.department_transfers(destination_department_id);

-- Note: Existing records will have NULL values for these new columns
-- New transfers will populate these columns

-- Verify the changes
SELECT column_name, data_type, is_nullable 
FROM information_schema.columns 
WHERE table_name = 'department_transfers' 
AND table_schema = 'public'
ORDER BY ordinal_position;
