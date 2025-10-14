from django.db import models
from django.db.models import Q
import calendar
import datetime

# Helper to map month name to number
MONTH_TO_NUM = {name.lower(): i for i, name in enumerate(calendar.month_name) if name}

class EmployeeManager(models.Manager):
    """Custom manager to add utility methods for Employee."""

    def get_employee_bonus(self, employee_id: int, month_name: str) -> float:
        """
        Calculates the performance bonus for a specific employee and month
        based on positive KPI counts in the Performance model.
        """
        # Ensure 'Performance' model is imported or available in this scope
        from .models import Performance # Adjust import path as necessary

        month_num = MONTH_TO_NUM.get(month_name.lower())

        if not month_num:
            return 0.0

        current_year = datetime.date.today().year

        # Define your positive KPI criteria (must match the logic in your Performance records)
        POSITIVE_KPI_CRITERIA = ['excellent', 'achieved', 'outstanding'] # Example criteria

        # 1. Filter Performance records for the employee and month/year
        monthly_performances = Performance.objects.filter(
            employee_id=employee_id,
            date__year=current_year,
            date__month=month_num
        )

        # 2. Count records where the KPI matches positive criteria (case-insensitive)
        # Create a combined Q object for the filters
        q_filter = Q()
        for term in POSITIVE_KPI_CRITERIA:
            q_filter |= Q(kpi__icontains=term)

        positive_kpi_count = monthly_performances.filter(q_filter).count()

        # 3. Apply the bonus logic (e.g., $50 per positive KPI, max $500)
        BONUS_PER_POSITIVE_KPI = 50.00
        MAX_BONUS = 500.00

        calculated_bonus = min(positive_kpi_count * BONUS_PER_POSITIVE_KPI, MAX_BONUS)

        return calculated_bonus