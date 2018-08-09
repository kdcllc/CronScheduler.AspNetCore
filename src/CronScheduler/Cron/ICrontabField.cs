namespace CronScheduler.AspNetCore.Cron
{
    public interface ICrontabField
    {
        int GetFirst();
        int Next(int start);
        bool Contains(int value);
    }
}
