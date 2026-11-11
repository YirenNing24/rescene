import {test,expect} from '@playwright/test';
for(const size of [{width:1440,height:900},{width:390,height:844}]) {
 test('registration policy agreement and modals at '+size.width,async({page})=>{
  await page.setViewportSize(size);
  const registrations:Record<string,unknown>[]=[];
  await page.route('**/api/**',async route=>{
   const path=new URL(route.request().url()).pathname;
   if(path==='/api/auth/register') {registrations.push(route.request().postDataJSON());return route.fulfill({status:409,json:{error:{message:'Test account already exists.'}}});}
   if(path==='/api/session')return route.fulfill({status:401,json:{error:{message:'Please sign in.'}}});
   return route.fulfill({json:{catalog:[],checkout_enabled:false}});
  });
  await page.goto('/');
  await page.locator('.player-button').click();
  await page.getByRole('tab',{name:'Create account',exact:true}).click();
  const auth=page.getByRole('dialog').first();
  const agreement=page.getByRole('checkbox');
  await expect(agreement).not.toBeChecked();
  const create=page.getByRole('button',{name:'Create account',exact:true});
  await expect(create).toBeDisabled();
  await expect(page.getByText(/An unofficial, fan-made, nonprofit game/)).toBeVisible();
  await expect(page.getByText(/most likely a scammer/)).toBeVisible();
  for(const name of ['Terms & Conditions','Privacy Policy']) {
   await auth.locator('.policy-consent').getByRole('button',{name,exact:true}).click();
   const policy=page.getByRole('dialog').last();
   await expect(policy.getByRole('heading',{name,exact:true})).toBeVisible();
   await expect(policy.getByText('winterape25@gmail.com',{exact:true})).toHaveAttribute('href','mailto:winterape25@gmail.com');
   await policy.evaluate(element=>{element.scrollTop=element.scrollHeight;});
   expect(await policy.evaluate(element=>element.scrollTop)).toBeGreaterThan(100);
   await page.keyboard.press('Escape');
   await expect(page.getByRole('heading',{name,exact:true})).not.toBeVisible();
   await expect(agreement).not.toBeChecked();
   await expect(create).toBeDisabled();
  }
  await auth.getByLabel('Username',{exact:true}).fill('legal_test');
  await auth.getByLabel('Password',{exact:true}).fill('password123');
  await agreement.check();
  await expect(create).toBeEnabled();
  await page.screenshot({path:'../previews/legal-web-'+size.width+'.png',fullPage:true});
  await create.click();
  await expect.poll(()=>registrations.length).toBe(1);
  expect(registrations[0]).toMatchObject({accept_policies:true,terms_version:'2026-11-11',privacy_version:'2026-11-11'});
  await expect(page.getByText('Test account already exists.')).toBeVisible();
 });
}
