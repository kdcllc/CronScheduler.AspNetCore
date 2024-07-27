using CronSchedulerApp.Data;
using CronSchedulerApp.Jobs;
using CronSchedulerApp.Jobs.Startup;
using CronSchedulerApp.Services;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Polly;

#pragma warning disable SA1516 // ElementsMustBeSeparatedByBlankLine
var builder = WebApplication.CreateBuilder(args);

// Add services to the container.
builder.Services.Configure<CookiePolicyOptions>(options =>
{
    options.CheckConsentNeeded = context => true;
    options.MinimumSameSitePolicy = SameSiteMode.None;
});

builder.Services.AddDbContext<ApplicationDbContext>(options =>
{
    if (builder.Configuration["DatabaseProvider:Type"] == "Sqlite")
    {
        options.UseSqlite(builder.Configuration.GetConnectionString("SqliteConnection"));
    }

    if (builder.Configuration["DatabaseProvider:Type"] == "SqlServer")
    {
        options.UseSqlServer(builder.Configuration.GetConnectionString("SqlConnection"));
    }
});

builder.Services.AddDefaultIdentity<IdentityUser>()
    .AddEntityFrameworkStores<ApplicationDbContext>();

builder.Services.AddControllersWithViews();
builder.Services.AddRazorPages();

builder.Services.AddScheduler(builder =>
{
    builder.Services.AddSingleton<TorahVerses>();
    builder.Services
        .AddHttpClient<TorahService>()
        .AddTransientHttpErrorPolicy(p => p.RetryAsync());

    builder.AddJob<TorahQuoteJob, TorahQuoteJobOptions>();
    builder.Services.AddScoped<UserService>();
    builder.AddJob<UserJob, UserJobOptions>();

    builder.AddUnobservedTaskExceptionHandler(sp =>
    {
        var logger = sp.GetRequiredService<ILoggerFactory>().CreateLogger("CronJobs");
        return (sender, args) =>
        {
            logger?.LogError(args.Exception?.Message);
            args.SetObserved();
        };
    });
});

builder.Services.AddBackgroundQueuedService(applicationOnStopWaitForTasksToComplete: true);
builder.Services.AddDatabaseDeveloperPageExceptionFilter();

builder.Services.AddStartupJob<SeedDatabaseStartupJob>();
builder.Services.AddStartupJob<TestStartupJob>();

builder.Logging.AddConsole();
builder.Logging.AddDebug();
builder.Logging.AddConfiguration(builder.Configuration.GetSection("Logging"));

var app = builder.Build();

// Configure the HTTP request pipeline.
if (app.Environment.IsDevelopment())
{
    app.UseDeveloperExceptionPage();
    app.UseMigrationsEndPoint();
}
else
{
    app.UseExceptionHandler("/Home/Error");
    app.UseHsts();
}

app.UseHttpsRedirection();
app.UseStaticFiles();
app.UseCookiePolicy();
app.UseAuthentication();
app.UseRouting();

app.MapControllers();
app.MapDefaultControllerRoute();
app.MapRazorPages();

await app.RunStartupJobsAsync();
await app.RunAsync();
#pragma warning restore SA1516 // ElementsMustBeSeparatedByBlankLine
