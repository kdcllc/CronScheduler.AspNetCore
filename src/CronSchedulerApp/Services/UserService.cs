using System;
using System.Collections.Generic;
using System.Linq;
using System.Security.Claims;
using System.Threading.Tasks;

using CronSchedulerApp.Data;

using Microsoft.AspNetCore.Identity;

namespace CronSchedulerApp.Services
{
    /// <summary>
    /// Demonstrates utilization of the scoped/transient objects inside of the jobs.
    /// </summary>
    public class UserService
    {
        private readonly UserManager<IdentityUser> _userManager;
        private readonly ApplicationDbContext _dbContext;

        public UserService(
            ApplicationDbContext dbContext,
            UserManager<IdentityUser> userManager)
        {
            _dbContext = dbContext ?? throw new ArgumentNullException(nameof(dbContext));
            _userManager = userManager ?? throw new ArgumentNullException(nameof(userManager));
        }

        public async Task<IdentityUser> GetUserByEmail(string email)
        {
            return await _userManager.FindByEmailAsync(email);
        }

        public async Task<IdentityResult> AddClaimAsync(IdentityUser user, Claim claim)
        {
            return await _userManager.AddClaimAsync(user, claim);
        }

        public IEnumerable<IdentityUser> GetUsers()
        {
            return _dbContext.Users.ToList();
        }
    }
}
